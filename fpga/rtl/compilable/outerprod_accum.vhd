library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rbm_types.all;

entity outerprod_accum is
  generic (
    I_TILE : integer := 64;
    H_TILE : integer := 64
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    clr_pos      : in  std_logic;
    clr_neg      : in  std_logic;
    neg_phase    : in  std_logic;
    sample_valid : in  std_logic;
    v_i          : in  s8_array(0 to I_TILE-1);
    h_p          : in  u16_array(0 to H_TILE-1);
    last_sample  : in  std_logic;
    done         : out std_logic
  );
end entity;

architecture rtl of outerprod_accum is
  constant N : integer := I_TILE * H_TILE;
  type acc_array is array (0 to N-1) of signed(31 downto 0);

  signal acc_pos : acc_array := (others => (others => '0'));
  signal acc_neg : acc_array := (others => (others => '0'));

  type st_t is (IDLE, ACCUM, FIN);
  signal st : st_t := IDLE;

  signal done_r : std_logic := '0';
begin
  done <= done_r;

  process (clk)
    variable a    : integer;
    variable prod : signed(23 downto 0);
    variable ext  : signed(31 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st <= IDLE;
        done_r <= '0';
        for idx in 0 to N-1 loop
          acc_pos(idx) <= (others => '0');
          acc_neg(idx) <= (others => '0');
        end loop;
      else
        done_r <= '0';
        if clr_pos = '1' then
          for idx in 0 to N-1 loop
            acc_pos(idx) <= (others => '0');
          end loop;
        end if;
        if clr_neg = '1' then
          for idx in 0 to N-1 loop
            acc_neg(idx) <= (others => '0');
          end loop;
        end if;

        case st is
          when IDLE =>
            if sample_valid = '1' then
              st <= ACCUM;
            end if;

          when ACCUM =>
            for i in 0 to I_TILE-1 loop
              for h in 0 to H_TILE-1 loop
                a := i * H_TILE + h;
                prod := signed(resize(v_i(i), 16)) * signed(h_p(h));
                ext := resize(prod, 32);
                if neg_phase = '0' then
                  acc_pos(a) <= acc_pos(a) + ext;
                else
                  acc_neg(a) <= acc_neg(a) + ext;
                end if;
              end loop;
            end loop;
            if last_sample = '1' then
              st <= FIN;
            end if;

          when FIN =>
            done_r <= '1';
            st <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
