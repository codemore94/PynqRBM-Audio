library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rbm_types.all;

entity rbm_core_min is
  generic (
    I_DIM : integer := 256
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    start : in  std_logic;
    busy  : out std_logic;
    v_mem : in  s8_array(0 to I_DIM-1);
    w_col : in  s16_array(0 to I_DIM-1);
    b_j   : in  signed(31 downto 0);
    p_j   : out std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of rbm_core_min is
  type st_t is (IDLE, ACC, ACT);
  signal st  : st_t := IDLE;
  signal i   : unsigned(15 downto 0) := (others => '0');
  signal acc : signed(31 downto 0) := (others => '0');
  signal sig_y : std_logic_vector(15 downto 0);

  function to_index(x : unsigned) return integer is
  begin
    return to_integer(x);
  end function;
begin
  busy <= '1' when st /= IDLE else '0';

  u_sig : entity work.sigmoid_lut
    port map (
      clk => clk,
      x   => std_logic_vector(acc(21 downto 6)),
      y   => sig_y
    );

  process (clk)
    variable idx : integer;
    variable prod : signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st  <= IDLE;
        i   <= (others => '0');
        acc <= (others => '0');
      else
        case st is
          when IDLE =>
            if start = '1' then
              i   <= (others => '0');
              acc <= b_j;
              st  <= ACC;
            end if;

          when ACC =>
            idx := to_index(i);
            prod := signed(resize(v_mem(idx), 16)) * signed(w_col(idx));
            acc <= acc + resize(prod, 32);
            i <= i + 1;
            if i = to_unsigned(I_DIM-1, i'length) then
              st <= ACT;
            end if;

          when ACT =>
            p_j <= sig_y;
            st <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
