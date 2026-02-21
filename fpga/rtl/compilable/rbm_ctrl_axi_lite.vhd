library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rbm_ctrl_axi_lite is
  generic (
    ADDR_W : integer := 8
  );
  port (
    ACLK       : in  std_logic;
    ARESETn    : in  std_logic;
    S_AWADDR   : in  std_logic_vector(31 downto 0);
    S_AWVALID  : in  std_logic;
    S_AWREADY  : out std_logic;
    S_WDATA    : in  std_logic_vector(31 downto 0);
    S_WSTRB    : in  std_logic_vector(3 downto 0);
    S_WVALID   : in  std_logic;
    S_WREADY   : out std_logic;
    S_BRESP    : out std_logic_vector(1 downto 0);
    S_BVALID   : out std_logic;
    S_BREADY   : in  std_logic;
    S_ARADDR   : in  std_logic_vector(31 downto 0);
    S_ARVALID  : in  std_logic;
    S_ARREADY  : out std_logic;
    S_RDATA    : out std_logic_vector(31 downto 0);
    S_RRESP    : out std_logic_vector(1 downto 0);
    S_RVALID   : out std_logic;
    S_RREADY   : in  std_logic;
    ctrl_start      : out std_logic;
    ctrl_soft_rst   : out std_logic;
    ctrl_mode_train : out std_logic;
    ctrl_determ     : out std_logic;
    ctrl_dma_en     : out std_logic;
    i_dim       : out std_logic_vector(15 downto 0);
    h_dim       : out std_logic_vector(15 downto 0);
    frame_len   : out std_logic_vector(15 downto 0);
    k_dim       : out std_logic_vector(7 downto 0);
    scale_shift : out std_logic_vector(4 downto 0);
    rng_seed    : out std_logic_vector(15 downto 0);
    tile_i      : out std_logic_vector(15 downto 0);
    tile_h      : out std_logic_vector(15 downto 0);
    batch_size  : out std_logic_vector(15 downto 0);
    epochs      : out std_logic_vector(15 downto 0);
    lr          : out std_logic_vector(15 downto 0);
    mom         : out std_logic_vector(15 downto 0);
    wd          : out std_logic_vector(15 downto 0);
    accum_clr_pos : out std_logic;
    accum_clr_neg : out std_logic;
    w_base_lo   : out std_logic_vector(31 downto 0);
    w_base_hi   : out std_logic_vector(31 downto 0);
    b_vis_base  : out std_logic_vector(31 downto 0);
    b_hid_base  : out std_logic_vector(31 downto 0);
    data_base_lo: out std_logic_vector(31 downto 0);
    data_base_hi: out std_logic_vector(31 downto 0);
    stat_busy       : in  std_logic;
    stat_done       : in  std_logic;
    stat_err        : in  std_logic;
    stat_batch_done : in  std_logic;
    stat_epoch_done : in  std_logic;
    stat_flags      : in  std_logic_vector(31 downto 0);
    irq         : out std_logic;
    ie_done     : in  std_logic;
    ie_batch    : in  std_logic;
    ie_epoch    : in  std_logic;
    mem_addr    : out std_logic_vector(31 downto 0);
    mem_wdata   : out std_logic_vector(31 downto 0);
    mem_wen     : out std_logic;
    mem_sel     : out std_logic_vector(2 downto 0);
    mem_rdata   : in  std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of rbm_ctrl_axi_lite is
  signal REG_CONTROL    : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_STATUS     : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_INT_EN     : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_INT_ST     : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_I_DIM      : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_H_DIM      : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_K_DIM      : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_FRAME_LEN  : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_SCALE_SHIFT: std_logic_vector(31 downto 0) := (others => '0');
  signal REG_RNG_SEED   : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_TILE_IH    : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_BATCH      : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_EPOCHS     : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_LR_MOM     : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_WD         : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_STATS      : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_W_BASE_LO  : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_W_BASE_HI  : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_B_VIS_BASE : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_B_HID_BASE : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_DATA_BASE_LO : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_DATA_BASE_HI : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_ACCUM_CTRL : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_MEM_ADDR   : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_MEM_WDATA  : std_logic_vector(31 downto 0) := (others => '0');
  signal REG_MEM_CTRL   : std_logic_vector(31 downto 0) := (others => '0');

  signal awaddr_latched : std_logic_vector(ADDR_W-1 downto 0) := (others => '0');
  signal araddr_latched : std_logic_vector(ADDR_W-1 downto 0) := (others => '0');

  function apply_wstrb(
    cur   : std_logic_vector(31 downto 0);
    wdata : std_logic_vector(31 downto 0);
    wstrb : std_logic_vector(3 downto 0)
  ) return std_logic_vector is
    variable res : std_logic_vector(31 downto 0);
  begin
    res := cur;
    if wstrb(0) = '1' then res(7 downto 0)   := wdata(7 downto 0);   end if;
    if wstrb(1) = '1' then res(15 downto 8)  := wdata(15 downto 8);  end if;
    if wstrb(2) = '1' then res(23 downto 16) := wdata(23 downto 16); end if;
    if wstrb(3) = '1' then res(31 downto 24) := wdata(31 downto 24); end if;
    return res;
  end function;

  signal any_int : std_logic;
begin
  ctrl_start      <= REG_CONTROL(0);
  ctrl_soft_rst   <= REG_CONTROL(1);
  ctrl_mode_train <= REG_CONTROL(2);
  ctrl_determ     <= REG_CONTROL(3);
  ctrl_dma_en     <= REG_CONTROL(4);

  i_dim       <= REG_I_DIM(15 downto 0);
  h_dim       <= REG_H_DIM(15 downto 0);
  k_dim       <= REG_K_DIM(7 downto 0);
  frame_len   <= REG_FRAME_LEN(15 downto 0);
  scale_shift <= REG_SCALE_SHIFT(4 downto 0);
  rng_seed    <= REG_RNG_SEED(15 downto 0);
  tile_i      <= REG_TILE_IH(15 downto 0);
  tile_h      <= REG_TILE_IH(31 downto 16);
  batch_size  <= REG_BATCH(15 downto 0);
  epochs      <= REG_EPOCHS(15 downto 0);
  lr          <= REG_LR_MOM(15 downto 0);
  mom         <= REG_LR_MOM(31 downto 16);
  wd          <= REG_WD(15 downto 0);
  accum_clr_pos <= REG_ACCUM_CTRL(0);
  accum_clr_neg <= REG_ACCUM_CTRL(1);

  w_base_lo    <= REG_W_BASE_LO;
  w_base_hi    <= REG_W_BASE_HI;
  b_vis_base   <= REG_B_VIS_BASE;
  b_hid_base   <= REG_B_HID_BASE;
  data_base_lo <= REG_DATA_BASE_LO;
  data_base_hi <= REG_DATA_BASE_HI;

  mem_addr  <= REG_MEM_ADDR;
  mem_wdata <= REG_MEM_WDATA;
  mem_sel   <= REG_MEM_CTRL(2 downto 0);

  any_int <= (ie_done and stat_done) or
             (ie_batch and stat_batch_done) or
             (ie_epoch and stat_epoch_done);
  irq <= any_int;

  S_BRESP <= "00";
  S_RRESP <= "00";

  process (ACLK)
  begin
    if rising_edge(ACLK) then
      if ARESETn = '0' then
        S_AWREADY <= '1';
        S_WREADY  <= '1';
        S_BVALID  <= '0';
        S_ARREADY <= '1';
        S_RVALID  <= '0';
        S_RDATA   <= (others => '0');
        awaddr_latched <= (others => '0');
        araddr_latched <= (others => '0');

        REG_CONTROL <= (others => '0');
        REG_INT_EN  <= (others => '0');
        REG_INT_ST  <= (others => '0');
        REG_I_DIM   <= std_logic_vector(to_unsigned(256, 32));
        REG_H_DIM   <= std_logic_vector(to_unsigned(256, 32));
        REG_K_DIM   <= std_logic_vector(to_unsigned(1, 32));
        REG_FRAME_LEN <= std_logic_vector(to_unsigned(1, 32));
        REG_SCALE_SHIFT <= (others => '0');
        REG_RNG_SEED <= std_logic_vector(to_unsigned(1, 32));
        REG_TILE_IH <= (others => '0');
        REG_BATCH   <= std_logic_vector(to_unsigned(1, 32));
        REG_EPOCHS  <= std_logic_vector(to_unsigned(1, 32));
        REG_LR_MOM  <= (others => '0');
        REG_WD      <= (others => '0');
        REG_W_BASE_LO <= (others => '0');
        REG_W_BASE_HI <= (others => '0');
        REG_B_VIS_BASE <= (others => '0');
        REG_B_HID_BASE <= (others => '0');
        REG_DATA_BASE_LO <= (others => '0');
        REG_DATA_BASE_HI <= (others => '0');
        REG_ACCUM_CTRL <= (others => '0');
        REG_MEM_ADDR <= (others => '0');
        REG_MEM_WDATA <= (others => '0');
        REG_MEM_CTRL <= (others => '0');
        mem_wen <= '0';
      else
        mem_wen <= '0';

        if S_AWVALID = '1' and S_WVALID = '1' and S_BVALID = '0' then
          awaddr_latched <= S_AWADDR(ADDR_W-1 downto 0);
          S_BVALID <= '1';
          case S_AWADDR(ADDR_W-1 downto 2) is
            when "000000" => REG_CONTROL <= apply_wstrb(REG_CONTROL, S_WDATA, S_WSTRB);
            when "000010" => REG_I_DIM   <= apply_wstrb(REG_I_DIM, S_WDATA, S_WSTRB);
            when "000011" => REG_H_DIM   <= apply_wstrb(REG_H_DIM, S_WDATA, S_WSTRB);
            when "000100" => REG_K_DIM   <= apply_wstrb(REG_K_DIM, S_WDATA, S_WSTRB);
            when "000101" => REG_FRAME_LEN <= apply_wstrb(REG_FRAME_LEN, S_WDATA, S_WSTRB);
            when "000110" => REG_SCALE_SHIFT <= apply_wstrb(REG_SCALE_SHIFT, S_WDATA, S_WSTRB);
            when "000111" => REG_RNG_SEED <= apply_wstrb(REG_RNG_SEED, S_WDATA, S_WSTRB);
            when "001000" => REG_INT_EN <= apply_wstrb(REG_INT_EN, S_WDATA, S_WSTRB);
            when "001010" => REG_TILE_IH <= apply_wstrb(REG_TILE_IH, S_WDATA, S_WSTRB);
            when "001011" => REG_BATCH   <= apply_wstrb(REG_BATCH, S_WDATA, S_WSTRB);
            when "001100" => REG_EPOCHS  <= apply_wstrb(REG_EPOCHS, S_WDATA, S_WSTRB);
            when "001101" => REG_LR_MOM  <= apply_wstrb(REG_LR_MOM, S_WDATA, S_WSTRB);
            when "001110" => REG_WD      <= apply_wstrb(REG_WD, S_WDATA, S_WSTRB);
            when "010000" => REG_W_BASE_LO <= apply_wstrb(REG_W_BASE_LO, S_WDATA, S_WSTRB);
            when "010001" => REG_W_BASE_HI <= apply_wstrb(REG_W_BASE_HI, S_WDATA, S_WSTRB);
            when "010010" => REG_B_VIS_BASE <= apply_wstrb(REG_B_VIS_BASE, S_WDATA, S_WSTRB);
            when "010011" => REG_B_HID_BASE <= apply_wstrb(REG_B_HID_BASE, S_WDATA, S_WSTRB);
            when "010100" => REG_DATA_BASE_LO <= apply_wstrb(REG_DATA_BASE_LO, S_WDATA, S_WSTRB);
            when "010101" => REG_DATA_BASE_HI <= apply_wstrb(REG_DATA_BASE_HI, S_WDATA, S_WSTRB);
            when "011010" => REG_ACCUM_CTRL <= apply_wstrb(REG_ACCUM_CTRL, S_WDATA, S_WSTRB);
            when "011011" => REG_MEM_ADDR <= apply_wstrb(REG_MEM_ADDR, S_WDATA, S_WSTRB);
            when "011100" =>
              REG_MEM_WDATA <= apply_wstrb(REG_MEM_WDATA, S_WDATA, S_WSTRB);
              mem_wen <= '1';
            when "011110" => REG_MEM_CTRL <= apply_wstrb(REG_MEM_CTRL, S_WDATA, S_WSTRB);
            when others => null;
          end case;
        elsif S_BVALID = '1' and S_BREADY = '1' then
          S_BVALID <= '0';
        end if;

        if S_ARVALID = '1' and S_RVALID = '0' then
          araddr_latched <= S_ARADDR(ADDR_W-1 downto 0);
          S_RVALID <= '1';
          case S_ARADDR(ADDR_W-1 downto 2) is
            when "000000" => S_RDATA <= REG_CONTROL;
            when "000001" => S_RDATA <= REG_STATUS;
            when "000010" => S_RDATA <= REG_I_DIM;
            when "000011" => S_RDATA <= REG_H_DIM;
            when "000100" => S_RDATA <= REG_K_DIM;
            when "000101" => S_RDATA <= REG_FRAME_LEN;
            when "000110" => S_RDATA <= REG_SCALE_SHIFT;
            when "000111" => S_RDATA <= REG_RNG_SEED;
            when "001000" => S_RDATA <= REG_INT_EN;
            when "001001" => S_RDATA <= REG_INT_ST;
            when "001010" => S_RDATA <= REG_TILE_IH;
            when "001011" => S_RDATA <= REG_BATCH;
            when "001100" => S_RDATA <= REG_EPOCHS;
            when "001101" => S_RDATA <= REG_LR_MOM;
            when "001110" => S_RDATA <= REG_WD;
            when "001111" => S_RDATA <= REG_STATS;
            when "010000" => S_RDATA <= REG_W_BASE_LO;
            when "010001" => S_RDATA <= REG_W_BASE_HI;
            when "010010" => S_RDATA <= REG_B_VIS_BASE;
            when "010011" => S_RDATA <= REG_B_HID_BASE;
            when "010100" => S_RDATA <= REG_DATA_BASE_LO;
            when "010101" => S_RDATA <= REG_DATA_BASE_HI;
            when "011010" => S_RDATA <= REG_ACCUM_CTRL;
            when "011011" => S_RDATA <= REG_MEM_ADDR;
            when "011100" => S_RDATA <= REG_MEM_WDATA;
            when "011101" => S_RDATA <= mem_rdata;
            when "011110" => S_RDATA <= REG_MEM_CTRL;
            when others   => S_RDATA <= (others => '0');
          end case;
        elsif S_RVALID = '1' and S_RREADY = '1' then
          S_RVALID <= '0';
        end if;
      end if;
    end if;
  end process;

  process (stat_busy, stat_done, stat_err, stat_batch_done, stat_epoch_done)
  begin
    REG_STATUS <= (others => '0');
    REG_STATUS(0) <= stat_busy;
    REG_STATUS(1) <= stat_done;
    REG_STATUS(2) <= stat_err;
    REG_STATUS(3) <= stat_batch_done;
    REG_STATUS(4) <= stat_epoch_done;
  end process;

  REG_STATS <= stat_flags;
end architecture;
