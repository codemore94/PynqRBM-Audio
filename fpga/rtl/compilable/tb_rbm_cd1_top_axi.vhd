library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rbm_cd1_top_axi is
end entity;

architecture sim of tb_rbm_cd1_top_axi is
  constant I_DIM : integer := 4;
  constant H_DIM : integer := 4;

  signal clk  : std_logic := '0';
  signal rstn : std_logic := '0';

  signal S_AWADDR  : std_logic_vector(31 downto 0) := (others => '0');
  signal S_AWVALID : std_logic := '0';
  signal S_AWREADY : std_logic;
  signal S_WDATA   : std_logic_vector(31 downto 0) := (others => '0');
  signal S_WSTRB   : std_logic_vector(3 downto 0) := (others => '0');
  signal S_WVALID  : std_logic := '0';
  signal S_WREADY  : std_logic;
  signal S_BRESP   : std_logic_vector(1 downto 0);
  signal S_BVALID  : std_logic;
  signal S_BREADY  : std_logic := '0';
  signal S_ARADDR  : std_logic_vector(31 downto 0) := (others => '0');
  signal S_ARVALID : std_logic := '0';
  signal S_ARREADY : std_logic;
  signal S_RDATA   : std_logic_vector(31 downto 0);
  signal S_RRESP   : std_logic_vector(1 downto 0);
  signal S_RVALID  : std_logic;
  signal S_RREADY  : std_logic := '0';
  signal irq       : std_logic;

  constant clk_period : time := 10 ns;

  constant REG_CONTROL     : std_logic_vector(31 downto 0) := x"00000000";
  constant REG_STATUS      : std_logic_vector(31 downto 0) := x"00000004";
  constant REG_I_DIM       : std_logic_vector(31 downto 0) := x"00000008";
  constant REG_H_DIM       : std_logic_vector(31 downto 0) := x"0000000C";
  constant REG_K_DIM       : std_logic_vector(31 downto 0) := x"00000010";
  constant REG_FRAME_LEN   : std_logic_vector(31 downto 0) := x"00000014";
  constant REG_SCALE_SHIFT : std_logic_vector(31 downto 0) := x"00000018";
  constant REG_RNG_SEED    : std_logic_vector(31 downto 0) := x"0000001C";
  constant REG_BATCH       : std_logic_vector(31 downto 0) := x"0000002C";
  constant REG_EPOCHS      : std_logic_vector(31 downto 0) := x"00000030";
  constant REG_LR_MOM      : std_logic_vector(31 downto 0) := x"00000034";
  constant REG_WD          : std_logic_vector(31 downto 0) := x"00000038";
  constant REG_MEM_ADDR    : std_logic_vector(31 downto 0) := x"0000006C";
  constant REG_MEM_WDATA   : std_logic_vector(31 downto 0) := x"00000070";
  constant REG_MEM_RDATA   : std_logic_vector(31 downto 0) := x"00000074";
  constant REG_MEM_CTRL    : std_logic_vector(31 downto 0) := x"00000078";

  procedure axi_write(addr : in std_logic_vector(31 downto 0);
                      data : in std_logic_vector(31 downto 0)) is
  begin
    wait until rising_edge(clk);
    S_AWADDR  <= addr;
    S_AWVALID <= '1';
    S_WDATA   <= data;
    S_WSTRB   <= x"F";
    S_WVALID  <= '1';
    S_BREADY  <= '1';
    wait until S_AWREADY = '1' and S_WREADY = '1';
    wait until rising_edge(clk);
    S_AWVALID <= '0';
    S_WVALID  <= '0';
    wait until S_BVALID = '1';
    wait until rising_edge(clk);
    S_BREADY  <= '0';
  end procedure;

  procedure axi_read(addr : in std_logic_vector(31 downto 0);
                     data : out std_logic_vector(31 downto 0)) is
  begin
    wait until rising_edge(clk);
    S_ARADDR  <= addr;
    S_ARVALID <= '1';
    S_RREADY  <= '1';
    wait until S_ARREADY = '1';
    wait until rising_edge(clk);
    S_ARVALID <= '0';
    wait until S_RVALID = '1';
    data := S_RDATA;
    wait until rising_edge(clk);
    S_RREADY <= '0';
  end procedure;

  procedure mem_write(sel : in std_logic_vector(2 downto 0);
                      addr : in std_logic_vector(31 downto 0);
                      data : in std_logic_vector(31 downto 0)) is
  begin
    axi_write(REG_MEM_CTRL, (31 downto 3 => '0') & sel);
    axi_write(REG_MEM_ADDR, addr);
    axi_write(REG_MEM_WDATA, data);
  end procedure;

  procedure mem_read(sel : in std_logic_vector(2 downto 0);
                     addr : in std_logic_vector(31 downto 0);
                     data : out std_logic_vector(31 downto 0)) is
  begin
    axi_write(REG_MEM_CTRL, (31 downto 3 => '0') & sel);
    axi_write(REG_MEM_ADDR, addr);
    axi_read(REG_MEM_RDATA, data);
  end procedure;

begin
  clk <= not clk after clk_period/2;

  dut : entity work.rbm_cd1_top_axi
    generic map (
      I_DIM => I_DIM,
      H_DIM => H_DIM
    )
    port map (
      ACLK => clk,
      ARESETn => rstn,
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
      irq => irq
    );

  process
    variable rdata : std_logic_vector(31 downto 0);
  begin
    rstn <= '0';
    wait for 5*clk_period;
    rstn <= '1';
    wait for 5*clk_period;

    axi_write(REG_I_DIM, std_logic_vector(to_unsigned(I_DIM, 32)));
    axi_write(REG_H_DIM, std_logic_vector(to_unsigned(H_DIM, 32)));
    axi_write(REG_K_DIM, std_logic_vector(to_unsigned(1, 32)));
    axi_write(REG_FRAME_LEN, std_logic_vector(to_unsigned(1, 32)));
    axi_write(REG_SCALE_SHIFT, (others => '0'));
    axi_write(REG_RNG_SEED, x"0000ACE1");
    axi_write(REG_BATCH, std_logic_vector(to_unsigned(1, 32)));
    axi_write(REG_EPOCHS, std_logic_vector(to_unsigned(1, 32)));
    axi_write(REG_LR_MOM, x"00000100");
    axi_write(REG_WD, (others => '0'));

    for i in 0 to I_DIM-1 loop
      if (i mod 2) = 1 then
        mem_write("000", std_logic_vector(to_unsigned(i, 32)), x"00000080");
      else
        mem_write("000", std_logic_vector(to_unsigned(i, 32)), x"00000000");
      end if;
    end loop;

    for i in 0 to I_DIM-1 loop
      mem_write("010", std_logic_vector(to_unsigned(i, 32)), x"00000000");
      for h in 0 to H_DIM-1 loop
        mem_write("001", std_logic_vector(to_unsigned(h, 16)) & std_logic_vector(to_unsigned(i, 16)), x"00000100");
      end loop;
    end loop;

    for h in 0 to H_DIM-1 loop
      mem_write("011", std_logic_vector(to_unsigned(h, 32)), x"00000000");
    end loop;

    axi_write(REG_CONTROL, x"00000001");

    for t in 0 to 2000 loop
      axi_read(REG_STATUS, rdata);
      if rdata(1) = '1' then
        report "DONE status=0x" & to_hstring(rdata);
        exit;
      end if;
      wait until rising_edge(clk);
    end loop;

    if rdata(1) = '0' then
      report "TIMEOUT waiting for done";
    end if;

    mem_read("001", x"00000000", rdata);
    report "w[0][0]=0x" & to_hstring(rdata);

    wait for 20*clk_period;
    std.env.stop;
    wait;
  end process;
end architecture;
