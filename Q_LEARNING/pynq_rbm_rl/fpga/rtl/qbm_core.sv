// hw/rtl/qrbm_core.sv
//
// Yksinkertainen RBM-free-energy -core yhdelle vektorille v.
// Laskenta (fixed-point):
//   linear_j   = b_h[j] + sum_i W[j][i] * v[i]
//   hidden_sum = sum_j softplus(linear_j)
//   vbias_sum  = sum_i b_v[i] * v[i]
//   F(v)       = -vbias_sum - hidden_sum
//
// Q(s,a) = -F(v) lasketaan ARM:lla tai Pynq-koodissa.

module qrbm_core #(
    parameter int N_VISIBLE     = 12,   // esim. 8 state-bittiä + 4 action-bit
    parameter int N_HIDDEN      = 32,
    parameter int W_WIDTH       = 16,   // W, b_v, b_h fixed-point leveys
    parameter int ACC_WIDTH     = 32    // akkumulaattorileveys (tuplaa tms.)
) (
    input  logic                     clk,
    input  logic                     rst_n,

    // Käynnistys + valmius
    input  logic                     start,   // pulssi tai level (1 clk)
    output logic                     busy,    // core laskee
    output logic                     done,    // pulssi, kun F_out valid

    // Syöte: näkyvä vektori v (kvantisoituna)
    input  logic signed [W_WIDTH-1:0] v_in [N_VISIBLE],

    // Painot ja biasit - tässä skeletonissa rekisteritaulukoina
    // (oikeasti nämä luetaan BRAMista / AXIsta yms.)
    input  logic signed [W_WIDTH-1:0] W     [N_HIDDEN][N_VISIBLE],
    input  logic signed [W_WIDTH-1:0] b_v   [N_VISIBLE],
    input  logic signed [W_WIDTH-1:0] b_h   [N_HIDDEN],

    // Lopputulos: F(v) fixed-point (sama formaatti kuin ACC_WIDTH)
    output logic signed [ACC_WIDTH-1:0] F_out
);

    // FSM-tilat
    typedef enum logic [2:0] {
        IDLE,
        VB_SUM,          // laske vbias_sum = sum_i b_v[i]*v[i]
        H_INIT,          // valmistele ensimmäinen hidden-unit
        H_ACCUM,         // MAC yli visible-indeksin i
        H_SOFTPLUS,      // softplus(linear_j)
        H_NEXT,          // seuraava hidden-yksikkö vai DONE
        DONE
    } state_t;

    state_t state, state_next;

    // Indeksit
    logic [$clog2(N_VISIBLE)-1:0] vis_idx;
    logic [$clog2(N_HIDDEN)-1:0]  hid_idx;

    // Akkumulaattorit
    logic signed [ACC_WIDTH-1:0] vbias_sum;
    logic signed [ACC_WIDTH-1:0] vbias_sum_next;

    logic signed [ACC_WIDTH-1:0] hidden_sum;
    logic signed [ACC_WIDTH-1:0] hidden_sum_next;

    // Yksittäisen hidden-unitin linear-termi
    logic signed [ACC_WIDTH-1:0] linear_acc;
    logic signed [ACC_WIDTH-1:0] linear_acc_next;

    // Softplus-LUTin ulostulo
    logic                       softplus_valid;
    logic signed [ACC_WIDTH-1:0] softplus_out;

    // Multiplikoinnin tulos: W * v
    logic signed [(W_WIDTH*2)-1:0] mul_temp;  // ennen laajennusta ACC_WIDTHiin
    logic signed [ACC_WIDTH-1:0]   mul_ext;

    // --- Combinational multiplikointi (yksi W[j][i] * v[i] per sykli) ---
    always_comb begin
        mul_temp = W[hid_idx][vis_idx] * v_in[vis_idx];
        // laajenna ACC_WIDTHiin ja tarvittaessa skaalauta (shift)
        mul_ext  = {{(ACC_WIDTH-(W_WIDTH*2)){mul_temp[(W_WIDTH*2)-1]}}, mul_temp};
        // HUOM: jos sinulla on frac-bittejä, tähän tulee >> FRACTION_BITS
    end

    // --- FSM seuraava tila & seuraavat akkumulaattorit ---
    always_comb begin
        // Oletukset (pidä vanhat arvot)
        state_next       = state;
        vbias_sum_next   = vbias_sum;
        hidden_sum_next  = hidden_sum;
        linear_acc_next  = linear_acc;

        done             = 1'b0;

        case (state)
            IDLE: begin
                if (start) begin
                    // nollaa summat ja indeksit ensimmäistä laskentaa varten
                    vbias_sum_next  = '0;
                    hidden_sum_next = '0;
                    state_next      = VB_SUM;
                end
            end

            // 1) lasketaan vbias_sum = sum_i b_v[i]*v[i]
            VB_SUM: begin
                // Käytetään samaa MAC-mekaniikkaa kuin hiddenillekin,
                // tässä vain W korvataan b_v:llä.
                // Tässä skeletonissa emme tee erillistä mulia, mutta voit
                // halutessasi käyttää samaa mul_temp v_in[i] * b_v[i].

                // Yksinkertaistettu pseudo:
                //   vbias_sum_next += b_v[vis_idx] * v_in[vis_idx];
                //   vis_idx++
                // Kun vis_idx == N_VISIBLE-1 -> siirry H_INIT

                state_next = H_INIT;  // tämä on skeleton; oikeasti tee loop
            end

            // 2) valmistellaan ensimmäinen hidden-j
            H_INIT: begin
                linear_acc_next = '0;
                // linear_acc <= b_h[hid_idx];
                // vis_idx <= 0;
                state_next = H_ACCUM;
            end

            // 3) MAC yli visible i: linear_j = b_h[j] + sum_i W[j][i]*v[i]
            H_ACCUM: begin
                // linear_acc_next = linear_acc + mul_ext;
                // vis_idx++

                // jos vis_idx == N_VISIBLE-1:
                //   state_next = H_SOFTPLUS;
                // muuten jää H_ACCUM

                state_next = H_SOFTPLUS;  // skeleton
            end

            // 4) Softplus-LUT kutsu: softplus(linear_j)
            H_SOFTPLUS: begin
                // Softplus-LUT toimii pipeline-tyyliin:
                // asetetaan sille input linear_acc ja odotetaan valid=1
                // kun softplus_valid=1:
                //   hidden_sum_next = hidden_sum + softplus_out
                //   state_next = H_NEXT
                state_next = H_NEXT;  // skeleton
            end

            // 5) Seuraava hidden-yksikkö vai DONE
            H_NEXT: begin
                // hid_idx++
                // jos hid_idx == N_HIDDEN-1:
                //    state_next = DONE
                // muuten:
                //    state_next = H_INIT
                state_next = DONE;  // skeleton
            end

            DONE: begin
                // laske lopullinen F_out = -vbias_sum - hidden_sum
                // asetetaan done-pulssi
                done        = 1'b1;
                state_next  = IDLE;
            end

            default: state_next = IDLE;
        endcase
    end

    // --- Sekventiaalinen tila- ja akkumulaattoripäivitys ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            vbias_sum  <= '0;
            hidden_sum <= '0;
            linear_acc <= '0;
            // indeksit nollaan
            // vis_idx <= '0;
            // hid_idx <= '0;
        end else begin
            state      <= state_next;
            vbias_sum  <= vbias_sum_next;
            hidden_sum <= hidden_sum_next;
            linear_acc <= linear_acc_next;

            // vis_idx, hid_idx päivitykset tekisit vastaavalla tyylillä,
            // esim. aina VB_SUM/H_ACCUM/H_NEXT -tiloissa.
        end
    end

    // --- F_out-laskenta ja busy-signaali ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            F_out <= '0;
            busy  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) busy <= 1'b1;
                end
                DONE: begin
                    // Täällä lasketaan varsinainen free energy lopuksi
                    // Huom! F(v) = -vbias_sum - hidden_sum
                    F_out <= -vbias_sum - hidden_sum;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

    // --- Softplus-LUT-kytkentä ---
    // Useimmiten toteutetaan erillisenä modulina, jolla on esim:
    //   - input clk
    //   - input signed [ACC_WIDTH-1:0] x
    //   - input valid_in
    //   - output valid_out
    //   - output signed [ACC_WIDTH-1:0] y

    softplus_lut #(
        .IN_WIDTH (ACC_WIDTH),
        .OUT_WIDTH(ACC_WIDTH)
    ) u_softplus_lut (
        .clk       (clk),
        .rst_n     (rst_n),
        .x_in      (linear_acc),
        .valid_in  (state == H_SOFTPLUS), // yksinkertainen ehto
        .y_out     (softplus_out),
        .valid_out (softplus_valid)
    );

endmodule
