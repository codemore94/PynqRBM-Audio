library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

entity sigmoid_lut is
  generic (
    IN_W   : integer := 16;
    OUT_W  : integer := 16;
    ADDR_W : integer := 10
  );
  port (
    clk : in  std_logic;
    x   : in  std_logic_vector(IN_W-1 downto 0);
    y   : out std_logic_vector(OUT_W-1 downto 0)
  );
end entity;

architecture rtl of sigmoid_lut is
  subtype rom_word_t is std_logic_vector(OUT_W-1 downto 0);
  type rom_t is array (0 to (2**ADDR_W)-1) of rom_word_t;

  impure function init_rom return rom_t is
    file f       : text open read_mode is "sigmoid_q6p10_q0p16.mem";
    variable l   : line;
    variable v   : std_logic_vector(OUT_W-1 downto 0);
    variable mem : rom_t := (others => (others => '0'));
    variable idx : integer := 0;
  begin
    while not endfile(f) loop
      readline(f, l);
      if l'length > 0 then
        hread(l, v);
        if idx <= mem'high then
          mem(idx) := v;
          idx := idx + 1;
        end if;
      end if;
    end loop;
    return mem;
  end function;

  signal rom  : rom_t := init_rom;
  signal addr : unsigned(ADDR_W-1 downto 0) := (others => '0');
begin
  process (x)
    variable bias  : unsigned(IN_W-1 downto 0);
    variable x_s_v : signed(IN_W-1 downto 0);
    variable x_u_v : unsigned(IN_W-1 downto 0);
  begin
    bias  := to_unsigned(2**(IN_W-1), IN_W);
    x_s_v := signed(x);
    x_u_v := unsigned(x_s_v) + bias;
    addr  <= x_u_v(IN_W-1 downto IN_W-ADDR_W);
  end process;

  process (clk)
  begin
    if rising_edge(clk) then
      y <= rom(to_integer(addr));
    end if;
  end process;
end architecture;
