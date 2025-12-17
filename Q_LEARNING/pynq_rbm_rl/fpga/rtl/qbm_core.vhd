-- qrbm_core.vhd (VHDL-93)
--
-- Simple RBM free-energy core for one visible vector v.
-- Fixed-point:
--   linear_j   = b_h[j] + sum_i W[j][i] * v[i]
--   hidden_sum = sum_j softplus(linear_j)
--   vbias_sum  = sum_i b_v[i] * v[i]
--   F(v)       = -vbias_sum - hidden_sum
--
-- NOTE (VHDL-93): inputs are flattened buses instead of array ports.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity qrbm_core is
  generic (
    N_VISIBLE : integer := 12;
    N_HIDDEN  : integer := 32;
    W_WIDTH   : integer := 16;
    ACC_WIDTH : integer := 32
  );
  port (
    clk   : in  std_logic;
    rst_n : in  std_logic;

    start : in  std_logic;   -- 1-cycle pulse recommended
    busy  : out std_logic;
    done  : out std_logic;   -- 1-cycle pulse when F_out updated

    -- Flattened inputs (element 0 in LSBs)
    v_in_flat : in std_logic_vector(N_VISIBLE*W_WIDTH-1 downto 0);

    -- W_flat holds N_HIDDEN*N_VISIBLE elements, linear index = j*N_VISIBLE + i
    W_flat    : in std_logic_vector(N_HIDDEN*N_VISIBLE*W_WIDTH-1 downto 0);

    b_v_flat  : in std_logic_vector(N_VISIBLE*W_WIDTH-1 downto 0);
    b_h_flat  : in std_logic_vector(N_HIDDEN*W_WIDTH-1 downto 0);

    -- Output
    F_out : out signed(ACC_WIDTH-1 downto 0)
  );
end entity;

architecture rtl of qrbm_core is

  ---------------------------------------------------------------------------
  -- Small helpers (VHDL-93 friendly)
  ---------------------------------------------------------------------------

  function clog2(n : positive) return natural is
    variable r : natural := 0;
    variable p : natural := 1;
  begin
    while p < n loop
      p := p * 2;
      r := r + 1;
    end loop;
    return r;
  end function;

  function idx_width(n : positive) return natural is
  begin
    if n <= 1 then
      return 1;
    else
      return clog2(n);
    end if;
  end function;

  -- Slice element idx out of a flattened vector where element0 is LSB.
  function get_elem_s(
    vec   : std_logic_vector;
    idx   : integer;
    width : integer
  ) return signed is
    variable hi : integer;
    variable lo : integer;
    variable s  : signed(width-1 downto 0);
  begin
    hi := (idx + 1) * width - 1;
    lo := idx * width;
    s  := signed(vec(hi downto lo));
    return s;
  end function;

  ---------------------------------------------------------------------------
  -- FSM
  ---------------------------------------------------------------------------

  type state_t is (IDLE, VB_SUM, H_INIT, H_ACCUM, H_SOFTPLUS, H_NEXT, DONE_S);

  constant VIS_W : natural := idx_width(N_VISIBLE);
  constant HID_W : natural := idx_width(N_HIDDEN);

  signal state, state_next : state_t;

  signal vis_idx, vis_idx_next : unsigned(VIS_W-1 downto 0);
  signal hid_idx, hid_idx_next : unsigned(HID_W-1 downto 0);

  signal vbias_sum,  vbias_sum_next  : signed(ACC_WIDTH-1 downto 0);
  signal hidden_sum, hidden_sum_next : signed(ACC_WIDTH-1 downto 0);
  signal linear_acc, linear_acc_next : signed(ACC_WIDTH-1 downto 0);

  -- multiply path
  signal mul_temp : signed((W_WIDTH*2)-1 downto 0);
  signal mul_ext  : signed(ACC_WIDTH-1 downto 0);

  -- softplus interface
  signal softplus_valid_in : std_logic;
  signal softplus_valid    : std_logic;
  signal softplus_out      : signed(ACC_WIDTH-1 downto 0);

  -- busy register (matches your SV style)
  signal busy_r : std_logic;

  ---------------------------------------------------------------------------
  -- Softplus LUT component (placeholder interface)
  ---------------------------------------------------------------------------
  component softplus_lut is
    generic (
      IN_WIDTH  : integer := 32;
      OUT_WIDTH : integer := 32
    );
    port (
      clk       : in  std_logic;
      rst_n     : in  std_logic;
      x_in      : in  signed(IN_WIDTH-1 downto 0);
      valid_in  : in  std_logic;
      y_out     : out signed(OUT_WIDTH-1 downto 0);
      valid_out : out std_logic
    );
  end component;

begin

  busy <= busy_r;
  done <= '1' when state = DONE_S else '0';

  -- If your softplus_lut expects a *pulse* (not a level), gate this with an
  -- "entering H_SOFTPLUS" pulse. This matches your SV skeleton (level-valid).
  softplus_valid_in <= '1' when state = H_SOFTPLUS else '0';

  u_softplus_lut : softplus_lut
    generic map (
      IN_WIDTH  => ACC_WIDTH,
      OUT_WIDTH => ACC_WIDTH
    )
    port map (
      clk       => clk,
      rst_n     => rst_n,
      x_in      => linear_acc,
      valid_in  => softplus_valid_in,
      y_out     => softplus_out,
      valid_out => softplus_valid
    );

  ---------------------------------------------------------------------------
  -- Combinational multiply: W[j][i] * v[i] (one per cycle)
  ---------------------------------------------------------------------------
  mul_comb : process(hid_idx, vis_idx, W_flat, v_in_flat)
    variable vi : integer;
    variable hj : integer;
    variable v_s : signed(W_WIDTH-1 downto 0);
    variable w_s : signed(W_WIDTH-1 downto 0);
    variable wlin : integer;
  begin
    vi := to_integer(vis_idx);
    hj := to_integer(hid_idx);

    v_s := get_elem_s(v_in_flat, vi, W_WIDTH);
    wlin := hj * N_VISIBLE + vi;
    w_s := get_elem_s(W_flat, wlin, W_WIDTH);

    mul_temp <= w_s * v_s;
    mul_ext  <= resize(mul_temp, ACC_WIDTH);
    -- NOTE: if you use fractional bits, you probably want:
    -- mul_ext <= resize( mul_temp sra FRACTION_BITS, ACC_WIDTH );
  end process;

  ---------------------------------------------------------------------------
  -- Next-state / next-data logic
  ---------------------------------------------------------------------------
  fsm_comb : process(state, start,
                     vis_idx, hid_idx,
                     vbias_sum, hidden_sum, linear_acc,
                     b_v_flat, b_h_flat, v_in_flat,
                     mul_ext, softplus_valid, softplus_out)
    variable vi : integer;
    variable hj : integer;

    variable v_s  : signed(W_WIDTH-1 downto 0);
    variable bv_s : signed(W_WIDTH-1 downto 0);
    variable bh_s : signed(W_WIDTH-1 downto 0);

    variable vb_mul : signed((W_WIDTH*2)-1 downto 0);
    variable vb_add : signed(ACC_WIDTH-1 downto 0);
  begin
    -- defaults (hold)
    state_next       <= state;
    vis_idx_next     <= vis_idx;
    hid_idx_next     <= hid_idx;

    vbias_sum_next   <= vbias_sum;
    hidden_sum_next  <= hidden_sum;
    linear_acc_next  <= linear_acc;

    vi := to_integer(vis_idx);
    hj := to_integer(hid_idx);

    case state is

      when IDLE =>
        if start = '1' then
          vbias_sum_next  <= (others => '0');
          hidden_sum_next <= (others => '0');
          linear_acc_next <= (others => '0');

          vis_idx_next    <= (others => '0');
          hid_idx_next    <= (others => '0');

          state_next      <= VB_SUM;
        end if;

      ---------------------------------------------------------------------
      -- vbias_sum = sum_i b_v[i] * v[i]
      ---------------------------------------------------------------------
      when VB_SUM =>
        v_s  := get_elem_s(v_in_flat, vi, W_WIDTH);
        bv_s := get_elem_s(b_v_flat,  vi, W_WIDTH);

        vb_mul := bv_s * v_s;
        vb_add := resize(vb_mul, ACC_WIDTH);

        vbias_sum_next <= vbias_sum + vb_add;

        if vi = (N_VISIBLE - 1) then
          vis_idx_next <= (others => '0');
          hid_idx_next <= (others => '0');
          state_next   <= H_INIT;
        else
          vis_idx_next <= vis_idx + 1;
          state_next   <= VB_SUM;
        end if;

      ---------------------------------------------------------------------
      -- Prepare a hidden unit: linear_acc = b_h[j]
      ---------------------------------------------------------------------
      when H_INIT =>
        bh_s := get_elem_s(b_h_flat, hj, W_WIDTH);

        linear_acc_next <= resize(bh_s, ACC_WIDTH);
        vis_idx_next    <= (others => '0');
        state_next      <= H_ACCUM;

      ---------------------------------------------------------------------
      -- linear_acc += W[j][i] * v[i]
      ---------------------------------------------------------------------
      when H_ACCUM =>
        linear_acc_next <= linear_acc + mul_ext;

        if vi = (N_VISIBLE - 1) then
          state_next <= H_SOFTPLUS;
        else
          vis_idx_next <= vis_idx + 1;
          state_next   <= H_ACCUM;
        end if;

      ---------------------------------------------------------------------
      -- Wait for softplus(linear_acc)
      ---------------------------------------------------------------------
      when H_SOFTPLUS =>
        if softplus_valid = '1' then
          hidden_sum_next <= hidden_sum + softplus_out;
          state_next      <= H_NEXT;
        else
          state_next      <= H_SOFTPLUS;
        end if;

      ---------------------------------------------------------------------
      -- Next hidden or done
      ---------------------------------------------------------------------
      when H_NEXT =>
        if hj = (N_HIDDEN - 1) then
          state_next <= DONE_S;
        else
          hid_idx_next <= hid_idx + 1;
          state_next   <= H_INIT;
        end if;

      when DONE_S =>
        state_next <= IDLE;

      when others =>
        state_next <= IDLE;

    end case;
  end process;

  ---------------------------------------------------------------------------
  -- State / registers
  ---------------------------------------------------------------------------
  regs : process(clk, rst_n)
  begin
    if rst_n = '0' then
      state      <= IDLE;
      vis_idx    <= (others => '0');
      hid_idx    <= (others => '0');

      vbias_sum  <= (others => '0');
      hidden_sum <= (others => '0');
      linear_acc <= (others => '0');
    elsif rising_edge(clk) then
      state      <= state_next;
      vis_idx    <= vis_idx_next;
      hid_idx    <= hid_idx_next;

      vbias_sum  <= vbias_sum_next;
      hidden_sum <= hidden_sum_next;
      linear_acc <= linear_acc_next;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- Output + busy (mirrors your SV: set on start, clear on DONE)
  ---------------------------------------------------------------------------
  out_and_busy : process(clk, rst_n)
  begin
    if rst_n = '0' then
      F_out  <= (others => '0');
      busy_r <= '0';
    elsif rising_edge(clk) then
      if state = IDLE then
        if start = '1' then
          busy_r <= '1';
        end if;
      elsif state = DONE_S then
        -- F(v) = -vbias_sum - hidden_sum
        F_out  <= -vbias_sum - hidden_sum;
        busy_r <= '0';
      end if;
    end if;
  end process;

end architecture;
