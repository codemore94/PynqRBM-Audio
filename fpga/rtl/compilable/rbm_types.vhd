library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package rbm_types is
  type s8_array  is array (natural range <>) of signed(7 downto 0);
  type s16_array is array (natural range <>) of signed(15 downto 0);
  type u16_array is array (natural range <>) of unsigned(15 downto 0);
  type s32_array is array (natural range <>) of signed(31 downto 0);
  type s16_2d    is array (natural range <>, natural range <>) of signed(15 downto 0);
end package;

package body rbm_types is
end package body;
