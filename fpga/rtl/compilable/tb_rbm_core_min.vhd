library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use work.rbm_types.all;

entity tb_rbm_core_min is
end entity;

architecture sim of tb_rbm_core_min is
  constant I_DIM : integer := 256;

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal start : std_logic := '0';
  signal busy  : std_logic;
  signal p_j   : std_logic_vector(15 downto 0);

  signal v_mem : s8_array(0 to I_DIM-1);
  signal w_col : s16_array(0 to I_DIM-1);
  signal b_j   : signed(31 downto 0);

  constant clk_period : time := 10 ns;

  procedure readmemh_s8(constant fname : in string; signal mem : out s8_array) is
    file f : text open read_mode is fname;
    variable l   : line;
    variable v   : std_logic_vector(7 downto 0);
    variable idx : integer := 0;
  begin
    while not endfile(f) and idx <= mem'high loop
      readline(f, l);
      if l'length > 0 then
        hread(l, v);
        mem(idx) <= signed(v);
        idx := idx + 1;
      end if;
    end loop;
  end procedure;

  procedure readmemh_s16(constant fname : in string; signal mem : out s16_array) is
    file f : text open read_mode is fname;
    variable l   : line;
    variable v   : std_logic_vector(15 downto 0);
    variable idx : integer := 0;
  begin
    while not endfile(f) and idx <= mem'high loop
      readline(f, l);
      if l'length > 0 then
        hread(l, v);
        mem(idx) <= signed(v);
        idx := idx + 1;
      end if;
    end loop;
  end procedure;

  procedure readmemh_s32(constant fname : in string; signal outv : out signed(31 downto 0)) is
    file f : text open read_mode is fname;
    variable l   : line;
    variable v   : std_logic_vector(31 downto 0);
  begin
    if not endfile(f) then
      readline(f, l);
      if l'length > 0 then
        hread(l, v);
        outv <= signed(v);
      end if;
    end if;
  end procedure;

begin
  clk <= not clk after clk_period/2;

  dut : entity work.rbm_core_min
    generic map (
      I_DIM => I_DIM
    )
    port map (
      clk => clk,
      rst => rst,
      start => start,
      busy => busy,
      v_mem => v_mem,
      w_col => w_col,
      b_j => b_j,
      p_j => p_j
    );

  process
    constant vecdir : string := "vectors";
  begin
    readmemh_s8(vecdir & "/v_mem.mem", v_mem);
    readmemh_s16(vecdir & "/w_col.mem", w_col);
    readmemh_s32(vecdir & "/bias.mem", b_j);

    rst <= '1';
    start <= '0';
    wait for 5*clk_period;
    rst <= '0';

    wait for 5*clk_period;
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';

    wait until busy = '1';
    wait until busy = '0';

    report "p_j=0x" & to_hstring(p_j);
    wait for 20*clk_period;
    std.env.stop;
    wait;
  end process;
end architecture;
