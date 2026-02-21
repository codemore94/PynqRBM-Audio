library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lfsr16 is
  port (
    clk  : in  std_logic;
    rst  : in  std_logic;
    seed : in  std_logic_vector(15 downto 0);
    rnd  : out std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of lfsr16 is
  signal s : std_logic_vector(15 downto 0) := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        s <= seed;
      else
        s <= s(14 downto 0) & (s(15) xor s(13) xor s(12) xor s(10));
      end if;
    end if;
  end process;

  rnd <= s;
end architecture;
