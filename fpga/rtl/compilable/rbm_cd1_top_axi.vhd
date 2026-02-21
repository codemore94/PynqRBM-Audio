library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rbm_types.all;

entity rbm_cd1_top_axi is
  generic (
    I_DIM : integer := 64;
    H_DIM : integer := 64
  );
  port (
    ACLK      : in  std_logic;
    ARESETn   : in  std_logic;
    S_AWADDR  : in  std_logic_vector(31 downto 0);
    S_AWVALID : in  std_logic;
    S_AWREADY : out std_logic;
    S_WDATA   : in  std_logic_vector(31 downto 0);
    S_WSTRB   : in  std_logic_vector(3 downto 0);
    S_WVALID  : in  std_logic;
    S_WREADY  : out std_logic;
    S_BRESP   : out std_logic_vector(1 downto 0);
    S_BVALID  : out std_logic;
    S_BREADY  : in  std_logic;
    S_ARADDR  : in  std_logic_vector(31 downto 0);
    S_ARVALID : in  std_logic;
    S_ARREADY : out std_logic;
    S_RDATA   : out std_logic_vector(31 downto 0);
    S_RRESP   : out std_logic_vector(1 downto 0);
    S_RVALID  : out std_logic;
    S_RREADY  : in  std_logic;
    irq       : out std_logic
  );
end entity;

architecture rtl of rbm_cd1_top_axi is
  signal ctrl_start      : std_logic;
  signal ctrl_soft_rst   : std_logic;
  signal ctrl_mode_train : std_logic;
  signal ctrl_determ     : std_logic;
  signal ctrl_dma_en     : std_logic;
  signal i_dim           : std_logic_vector(15 downto 0);
  signal h_dim           : std_logic_vector(15 downto 0);
  signal frame_len       : std_logic_vector(15 downto 0);
  signal k_dim           : std_logic_vector(7 downto 0);
  signal scale_shift     : std_logic_vector(4 downto 0);
  signal rng_seed        : std_logic_vector(15 downto 0);
  signal tile_i          : std_logic_vector(15 downto 0);
  signal tile_h          : std_logic_vector(15 downto 0);
  signal batch_size      : std_logic_vector(15 downto 0);
  signal epochs          : std_logic_vector(15 downto 0);
  signal lr              : std_logic_vector(15 downto 0);
  signal mom             : std_logic_vector(15 downto 0);
  signal wd              : std_logic_vector(15 downto 0);
  signal accum_clr_pos   : std_logic;
  signal accum_clr_neg   : std_logic;
  signal w_base_lo       : std_logic_vector(31 downto 0);
  signal w_base_hi       : std_logic_vector(31 downto 0);
  signal b_vis_base      : std_logic_vector(31 downto 0);
  signal b_hid_base      : std_logic_vector(31 downto 0);
  signal data_base_lo    : std_logic_vector(31 downto 0);
  signal data_base_hi    : std_logic_vector(31 downto 0);
  signal stat_busy       : std_logic;
  signal stat_done       : std_logic;
  signal stat_err        : std_logic;
  signal stat_batch_done : std_logic;
  signal stat_epoch_done : std_logic;
  signal stat_flags      : std_logic_vector(31 downto 0);
  signal ie_done         : std_logic;
  signal ie_batch        : std_logic;
  signal ie_epoch        : std_logic;

  signal mem_addr  : std_logic_vector(31 downto 0);
  signal mem_wdata : std_logic_vector(31 downto 0);
  signal mem_wen   : std_logic;
  signal mem_sel   : std_logic_vector(2 downto 0);
  signal mem_rdata : std_logic_vector(31 downto 0);

  signal v0 : s8_array(0 to I_DIM-1);
  signal v1 : s8_array(0 to I_DIM-1);
  signal w  : s16_2d(0 to I_DIM-1, 0 to H_DIM-1);
  signal b_vis : s16_array(0 to I_DIM-1);
  signal b_hid : s16_array(0 to H_DIM-1);
  signal h0_prob : u16_array(0 to H_DIM-1);
  signal h1_prob : u16_array(0 to H_DIM-1);
  signal h0_samp : s8_array(0 to H_DIM-1);

  signal rnd : std_logic_vector(15 downto 0);

  signal sig_in  : std_logic_vector(15 downto 0) := (others => '0');
  signal sig_out : std_logic_vector(15 downto 0);

  signal mem_i : unsigned(15 downto 0);
  signal mem_h : unsigned(15 downto 0);

  type st_t is (
    ST_IDLE,
    ST_POS_ACC,
    ST_POS_SIG,
    ST_POS_STORE,
    ST_NEG_ACC,
    ST_NEG_SIG,
    ST_NEG_STORE,
    ST_NEGH_ACC,
    ST_NEGH_SIG,
    ST_NEGH_STORE,
    ST_UPD_W,
    ST_UPD_BVIS,
    ST_UPD_BHID,
    ST_NEXT,
    ST_DONE
  );

  signal st : st_t := ST_IDLE;
  signal i_idx : unsigned(15 downto 0) := (others => '0');
  signal h_idx : unsigned(15 downto 0) := (others => '0');
  signal acc : signed(31 downto 0) := (others => '0');
  signal epoch_cnt : unsigned(15 downto 0) := (others => '0');
  signal batch_cnt : unsigned(15 downto 0) := (others => '0');
  signal done_latch : std_logic := '0';
  signal batch_pulse : std_logic := '0';
  signal epoch_pulse : std_logic := '0';

  signal pos_term    : signed(23 downto 0);
  signal neg_term    : signed(23 downto 0);
  signal delta_term  : signed(24 downto 0);
  signal scaled_term : signed(41 downto 0);
  signal dw_term     : signed(31 downto 0);
  signal diff_vis    : signed(7 downto 0);
  signal scaled_vis  : signed(23 downto 0);
  signal diff_hid    : signed(16 downto 0);
  signal scaled_hid  : signed(33 downto 0);

  function sample_bit(p : unsigned(15 downto 0);
                      determ : std_logic;
                      r : unsigned(15 downto 0)) return std_logic is
  begin
    if determ = '1' then
      if p >= x"8000" then
        return '1';
      else
        return '0';
      end if;
    else
      if r < p then
        return '1';
      else
        return '0';
      end if;
    end if;
  end function;

  function to_index(x : unsigned) return integer is
  begin
    return to_integer(x);
  end function;

begin
  u_rng : entity work.lfsr16
    port map (
      clk  => ACLK,
      rst  => (not ARESETn) or ctrl_soft_rst,
      seed => rng_seed,
      rnd  => rnd
    );

  u_sig : entity work.sigmoid_lut
    port map (
      clk => ACLK,
      x   => sig_in,
      y   => sig_out
    );

  u_ctrl : entity work.rbm_ctrl_axi_lite
    port map (
      ACLK => ACLK,
      ARESETn => ARESETn,
      S_AWADDR => S_AWADDR,
      S_AWVALID => S_AWVALID,
      S_AWREADY => S_AWREADY,
      S_WDATA => S_WDATA,
      S_WSTRB => S_WSTRB,
      S_WVALID => S_WVALID,
      S_WREADY => S_WREADY,
      S_BRESP => S_BRESP,
      S_BVALID => S_BVALID,
      S_BREADY => S_BREADY,
      S_ARADDR => S_ARADDR,
      S_ARVALID => S_ARVALID,
      S_ARREADY => S_ARREADY,
      S_RDATA => S_RDATA,
      S_RRESP => S_RRESP,
      S_RVALID => S_RVALID,
      S_RREADY => S_RREADY,
      ctrl_start => ctrl_start,
      ctrl_soft_rst => ctrl_soft_rst,
      ctrl_mode_train => ctrl_mode_train,
      ctrl_determ => ctrl_determ,
      ctrl_dma_en => ctrl_dma_en,
      i_dim => i_dim,
      h_dim => h_dim,
      frame_len => frame_len,
      k_dim => k_dim,
      scale_shift => scale_shift,
      rng_seed => rng_seed,
      tile_i => tile_i,
      tile_h => tile_h,
      batch_size => batch_size,
      epochs => epochs,
      lr => lr,
      mom => mom,
      wd => wd,
      accum_clr_pos => accum_clr_pos,
      accum_clr_neg => accum_clr_neg,
      w_base_lo => w_base_lo,
      w_base_hi => w_base_hi,
      b_vis_base => b_vis_base,
      b_hid_base => b_hid_base,
      data_base_lo => data_base_lo,
      data_base_hi => data_base_hi,
      stat_busy => stat_busy,
      stat_done => stat_done,
      stat_err => stat_err,
      stat_batch_done => stat_batch_done,
      stat_epoch_done => stat_epoch_done,
      stat_flags => stat_flags,
      irq => irq,
      ie_done => ie_done,
      ie_batch => ie_batch,
      ie_epoch => ie_epoch,
      mem_addr => mem_addr,
      mem_wdata => mem_wdata,
      mem_wen => mem_wen,
      mem_sel => mem_sel,
      mem_rdata => mem_rdata
    );

  ie_done  <= '1';
  ie_batch <= '1';
  ie_epoch <= '1';

  mem_i <= unsigned(mem_addr(15 downto 0));
  mem_h <= unsigned(mem_addr(31 downto 16));

  process (mem_sel, mem_i, mem_h, v0, w, b_vis, b_hid, h0_prob, h1_prob)
    variable rd : std_logic_vector(31 downto 0);
  begin
    rd := (others => '0');
    case mem_sel is
      when "000" =>
        if mem_i < to_unsigned(I_DIM, mem_i'length) then
          rd := (others => v0(to_integer(mem_i))(7));
          rd(7 downto 0) := std_logic_vector(v0(to_integer(mem_i)));
        end if;
      when "001" =>
        if mem_i < to_unsigned(I_DIM, mem_i'length) and mem_h < to_unsigned(H_DIM, mem_h'length) then
          rd := (others => w(to_integer(mem_i), to_integer(mem_h))(15));
          rd(15 downto 0) := std_logic_vector(w(to_integer(mem_i), to_integer(mem_h)));
        end if;
      when "010" =>
        if mem_i < to_unsigned(I_DIM, mem_i'length) then
          rd := (others => b_vis(to_integer(mem_i))(15));
          rd(15 downto 0) := std_logic_vector(b_vis(to_integer(mem_i)));
        end if;
      when "011" =>
        if mem_h < to_unsigned(H_DIM, mem_h'length) then
          rd := (others => b_hid(to_integer(mem_h))(15));
          rd(15 downto 0) := std_logic_vector(b_hid(to_integer(mem_h)));
        end if;
      when "100" =>
        if mem_h < to_unsigned(H_DIM, mem_h'length) then
          rd := x"0000" & std_logic_vector(h0_prob(to_integer(mem_h)));
        end if;
      when "101" =>
        if mem_h < to_unsigned(H_DIM, mem_h'length) then
          rd := x"0000" & std_logic_vector(h1_prob(to_integer(mem_h)));
        end if;
      when others =>
        rd := (others => '0');
    end case;
    mem_rdata <= rd;
  end process;

  process (ACLK)
    variable i : integer;
    variable j : integer;
  begin
    if rising_edge(ACLK) then
      if ARESETn = '0' then
        for i in 0 to I_DIM-1 loop
          v0(i) <= (others => '0');
          v1(i) <= (others => '0');
          b_vis(i) <= (others => '0');
          for j in 0 to H_DIM-1 loop
            w(i, j) <= (others => '0');
          end loop;
        end loop;
        for j in 0 to H_DIM-1 loop
          b_hid(j) <= (others => '0');
          h0_prob(j) <= (others => '0');
          h1_prob(j) <= (others => '0');
          h0_samp(j) <= (others => '0');
        end loop;
      else
        if mem_wen = '1' then
          case mem_sel is
            when "000" =>
              if mem_i < to_unsigned(I_DIM, mem_i'length) then
                v0(to_integer(mem_i)) <= signed(mem_wdata(7 downto 0));
              end if;
            when "001" =>
              if mem_i < to_unsigned(I_DIM, mem_i'length) and mem_h < to_unsigned(H_DIM, mem_h'length) then
                w(to_integer(mem_i), to_integer(mem_h)) <= signed(mem_wdata(15 downto 0));
              end if;
            when "010" =>
              if mem_i < to_unsigned(I_DIM, mem_i'length) then
                b_vis(to_integer(mem_i)) <= signed(mem_wdata(15 downto 0));
              end if;
            when "011" =>
              if mem_h < to_unsigned(H_DIM, mem_h'length) then
                b_hid(to_integer(mem_h)) <= signed(mem_wdata(15 downto 0));
              end if;
            when others =>
              null;
          end case;
        end if;
      end if;
    end if;
  end process;

  process (v0, v1, h0_prob, h1_prob, i_idx, h_idx, lr)
    variable i_i : integer;
    variable h_i : integer;
    variable lr_u : unsigned(15 downto 0);
  begin
    i_i := to_index(i_idx);
    h_i := to_index(h_idx);
    lr_u := unsigned(lr);

    pos_term   <= resize(signed(resize(v0(i_i), 16)) * signed(h0_prob(h_i)), 24);
    neg_term   <= resize(signed(resize(v1(i_i), 16)) * signed(h1_prob(h_i)), 24);
    delta_term <= resize(pos_term, 25) - resize(neg_term, 25);
    scaled_term <= resize(signed(resize(delta_term, 42)) * signed(resize(lr_u, 42)), 42);
    dw_term <= resize(shift_right(scaled_term, 16), 32);

    diff_vis   <= v0(i_i) - v1(i_i);
    scaled_vis <= resize(signed(resize(diff_vis, 24)) * signed(resize(lr_u, 24)), 24);

    diff_hid   <= signed(resize(h0_prob(h_i), 17)) - signed(resize(h1_prob(h_i), 17));
    scaled_hid <= resize(signed(resize(diff_hid, 34)) * signed(resize(lr_u, 34)), 34);
  end process;

  stat_busy       <= '1' when st /= ST_IDLE else '0';
  stat_done       <= done_latch;
  stat_err        <= '0';
  stat_batch_done <= batch_pulse;
  stat_epoch_done <= epoch_pulse;
  stat_flags      <= (31 downto 16 => '0') & std_logic_vector(epoch_cnt);

  process (ACLK)
    variable i_i : integer;
    variable h_i : integer;
  begin
    if rising_edge(ACLK) then
      if ARESETn = '0' then
        st <= ST_IDLE;
        i_idx <= (others => '0');
        h_idx <= (others => '0');
        acc <= (others => '0');
        sig_in <= (others => '0');
        epoch_cnt <= (others => '0');
        batch_cnt <= (others => '0');
        done_latch <= '0';
        batch_pulse <= '0';
        epoch_pulse <= '0';
      else
        batch_pulse <= '0';
        epoch_pulse <= '0';

        if ctrl_soft_rst = '1' then
          st <= ST_IDLE;
          i_idx <= (others => '0');
          h_idx <= (others => '0');
          acc <= (others => '0');
          sig_in <= (others => '0');
          epoch_cnt <= (others => '0');
          batch_cnt <= (others => '0');
          done_latch <= '0';
        else
          case st is
            when ST_IDLE =>
              if ctrl_start = '1' then
                done_latch <= '0';
                epoch_cnt <= (others => '0');
                batch_cnt <= (others => '0');
                i_idx <= (others => '0');
                h_idx <= (others => '0');
                st <= ST_POS_ACC;
              end if;

            when ST_POS_ACC =>
              i_i := to_index(i_idx);
              h_i := to_index(h_idx);
              if i_idx = to_unsigned(0, i_idx'length) then
                acc <= resize(b_hid(h_i), 32) +
                       signed(resize(v0(i_i), 16)) * signed(w(i_i, h_i));
              else
                acc <= acc + (signed(resize(v0(i_i), 16)) * signed(w(i_i, h_i)));
              end if;

              if i_idx = to_unsigned(I_DIM-1, i_idx'length) then
                i_idx <= (others => '0');
                st <= ST_POS_SIG;
              else
                i_idx <= i_idx + 1;
              end if;

            when ST_POS_SIG =>
              sig_in <= std_logic_vector(acc(21 downto 6));
              st <= ST_POS_STORE;

            when ST_POS_STORE =>
              h0_prob(to_index(h_idx)) <= unsigned(sig_out);
              if sample_bit(unsigned(sig_out), ctrl_determ, unsigned(rnd)) = '1' then
                h0_samp(to_index(h_idx)) <= to_signed(16#80#, 8);
              else
                h0_samp(to_index(h_idx)) <= to_signed(16#00#, 8);
              end if;

              if h_idx = to_unsigned(H_DIM-1, h_idx'length) then
                h_idx <= (others => '0');
                st <= ST_NEG_ACC;
              else
                h_idx <= h_idx + 1;
                st <= ST_POS_ACC;
              end if;

            when ST_NEG_ACC =>
              i_i := to_index(i_idx);
              h_i := to_index(h_idx);
              if h_idx = to_unsigned(0, h_idx'length) then
                acc <= resize(b_vis(i_i), 32) +
                       signed(resize(h0_samp(h_i), 16)) * signed(w(i_i, h_i));
              else
                acc <= acc + (signed(resize(h0_samp(h_i), 16)) * signed(w(i_i, h_i)));
              end if;

              if h_idx = to_unsigned(H_DIM-1, h_idx'length) then
                h_idx <= (others => '0');
                st <= ST_NEG_SIG;
              else
                h_idx <= h_idx + 1;
              end if;

            when ST_NEG_SIG =>
              sig_in <= std_logic_vector(acc(21 downto 6));
              st <= ST_NEG_STORE;

            when ST_NEG_STORE =>
              if sample_bit(unsigned(sig_out), ctrl_determ, unsigned(rnd)) = '1' then
                v1(to_index(i_idx)) <= to_signed(16#80#, 8);
              else
                v1(to_index(i_idx)) <= to_signed(16#00#, 8);
              end if;

              if i_idx = to_unsigned(I_DIM-1, i_idx'length) then
                i_idx <= (others => '0');
                st <= ST_NEGH_ACC;
              else
                i_idx <= i_idx + 1;
                st <= ST_NEG_ACC;
              end if;

            when ST_NEGH_ACC =>
              i_i := to_index(i_idx);
              h_i := to_index(h_idx);
              if i_idx = to_unsigned(0, i_idx'length) then
                acc <= resize(b_hid(h_i), 32) +
                       signed(resize(v1(i_i), 16)) * signed(w(i_i, h_i));
              else
                acc <= acc + (signed(resize(v1(i_i), 16)) * signed(w(i_i, h_i)));
              end if;

              if i_idx = to_unsigned(I_DIM-1, i_idx'length) then
                i_idx <= (others => '0');
                st <= ST_NEGH_SIG;
              else
                i_idx <= i_idx + 1;
              end if;

            when ST_NEGH_SIG =>
              sig_in <= std_logic_vector(acc(21 downto 6));
              st <= ST_NEGH_STORE;

            when ST_NEGH_STORE =>
              h1_prob(to_index(h_idx)) <= unsigned(sig_out);

              if h_idx = to_unsigned(H_DIM-1, h_idx'length) then
                h_idx <= (others => '0');
                st <= ST_UPD_W;
              else
                h_idx <= h_idx + 1;
                st <= ST_NEGH_ACC;
              end if;

            when ST_UPD_W =>
              i_i := to_index(i_idx);
              h_i := to_index(h_idx);
              w(i_i, h_i) <= w(i_i, h_i) + resize(shift_right(dw_term, 8), 16);

              if h_idx = to_unsigned(H_DIM-1, h_idx'length) then
                h_idx <= (others => '0');
                if i_idx = to_unsigned(I_DIM-1, i_idx'length) then
                  i_idx <= (others => '0');
                  st <= ST_UPD_BVIS;
                else
                  i_idx <= i_idx + 1;
                end if;
              else
                h_idx <= h_idx + 1;
              end if;

            when ST_UPD_BVIS =>
              i_i := to_index(i_idx);
              b_vis(i_i) <= b_vis(i_i) + resize(shift_right(scaled_vis, 8), 16);

              if i_idx = to_unsigned(I_DIM-1, i_idx'length) then
                i_idx <= (others => '0');
                st <= ST_UPD_BHID;
              else
                i_idx <= i_idx + 1;
              end if;

            when ST_UPD_BHID =>
              h_i := to_index(h_idx);
              b_hid(h_i) <= b_hid(h_i) + resize(shift_right(scaled_hid, 17), 16);

              if h_idx = to_unsigned(H_DIM-1, h_idx'length) then
                h_idx <= (others => '0');
                st <= ST_NEXT;
              else
                h_idx <= h_idx + 1;
              end if;

            when ST_NEXT =>
              if batch_cnt = unsigned(batch_size) - 1 then
                batch_cnt <= (others => '0');
                batch_pulse <= '1';
                if epoch_cnt = unsigned(epochs) - 1 then
                  epoch_cnt <= (others => '0');
                  epoch_pulse <= '1';
                  st <= ST_DONE;
                else
                  epoch_cnt <= epoch_cnt + 1;
                  st <= ST_POS_ACC;
                end if;
              else
                batch_cnt <= batch_cnt + 1;
                st <= ST_POS_ACC;
              end if;

            when ST_DONE =>
              done_latch <= '1';
              if ctrl_start = '0' then
                st <= ST_IDLE;
              end if;

            when others =>
              st <= ST_IDLE;
          end case;
        end if;
      end if;
    end if;
  end process;
end architecture;
