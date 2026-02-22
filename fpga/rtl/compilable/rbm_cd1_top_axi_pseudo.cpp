// Pseudocode representation of rbm_cd1_top_axi (SV/VHDL)

#include <cstdint>

struct RBM {
  int I_DIM = 64;
  int H_DIM = 64;

  // State
  int8_t   v0[64];
  int8_t   v1[64];
  int16_t  w[64][64];
  int16_t  b_vis[64];
  int16_t  b_hid[64];
  uint16_t h0_prob[64];
  uint16_t h1_prob[64];
  int8_t   h0_samp[64];

  // Control/params
  bool     ctrl_start = false;
  bool     ctrl_soft_rst = false;
  bool     ctrl_determ = false;
  uint16_t lr = 0;
  uint16_t batch_size = 1;
  uint16_t epochs = 1;

  // Status
  bool     stat_busy = false;
  bool     stat_done = false;
  bool     stat_batch_done = false;
  bool     stat_epoch_done = false;
  uint16_t epoch_cnt = 0;
  uint16_t batch_cnt = 0;

  // RNG and sigmoid
  uint16_t rnd16();
  uint16_t sigmoid_lut(uint16_t x);

  bool sample_bit(uint16_t p, bool determ, uint16_t r) {
    if (determ) return p >= 0x8000;
    return r < p;
  }

  void cd1_step() {
    // Positive phase: h0_prob/h0_samp
    for (int h = 0; h < H_DIM; h++) {
      int32_t acc = (int32_t)b_hid[h];
      for (int i = 0; i < I_DIM; i++) {
        acc += (int32_t)v0[i] * (int32_t)w[i][h];
      }
      uint16_t sig_in = (uint16_t)((acc >> 6) & 0xFFFF); // acc[21:6]
      uint16_t p = sigmoid_lut(sig_in);
      h0_prob[h] = p;
      h0_samp[h] = sample_bit(p, ctrl_determ, rnd16()) ? (int8_t)0x80 : (int8_t)0x00;
    }

    // Negative phase: reconstruct v1
    for (int i = 0; i < I_DIM; i++) {
      int32_t acc = (int32_t)b_vis[i];
      for (int h = 0; h < H_DIM; h++) {
        acc += (int32_t)h0_samp[h] * (int32_t)w[i][h];
      }
      uint16_t sig_in = (uint16_t)((acc >> 6) & 0xFFFF);
      uint16_t p = sigmoid_lut(sig_in);
      v1[i] = sample_bit(p, ctrl_determ, rnd16()) ? (int8_t)0x80 : (int8_t)0x00;
    }

    // Negative hidden probabilities h1
    for (int h = 0; h < H_DIM; h++) {
      int32_t acc = (int32_t)b_hid[h];
      for (int i = 0; i < I_DIM; i++) {
        acc += (int32_t)v1[i] * (int32_t)w[i][h];
      }
      uint16_t sig_in = (uint16_t)((acc >> 6) & 0xFFFF);
      h1_prob[h] = sigmoid_lut(sig_in);
    }

    // Weight update
    for (int i = 0; i < I_DIM; i++) {
      for (int h = 0; h < H_DIM; h++) {
        int32_t pos_term = (int32_t)v0[i] * (int32_t)h0_prob[h];
        int32_t neg_term = (int32_t)v1[i] * (int32_t)h1_prob[h];
        int32_t delta = pos_term - neg_term;
        int64_t scaled = (int64_t)delta * (int64_t)lr;
        int32_t dw = (int32_t)(scaled >> 16);
        w[i][h] = (int16_t)(w[i][h] + (dw >> 8));
      }
    }

    // Visible bias update
    for (int i = 0; i < I_DIM; i++) {
      int32_t diff = (int32_t)v0[i] - (int32_t)v1[i];
      int32_t scaled = diff * (int32_t)lr;
      b_vis[i] = (int16_t)(b_vis[i] + (scaled >> 8));
    }

    // Hidden bias update
    for (int h = 0; h < H_DIM; h++) {
      int32_t diff = (int32_t)h0_prob[h] - (int32_t)h1_prob[h];
      int32_t scaled = diff * (int32_t)lr;
      b_hid[h] = (int16_t)(b_hid[h] + (scaled >> 17));
    }
  }

  void run() {
    stat_done = false;
    epoch_cnt = 0;
    batch_cnt = 0;
    stat_busy = true;

    while (ctrl_start) {
      cd1_step();

      if (batch_cnt == batch_size - 1) {
        batch_cnt = 0;
        stat_batch_done = true;

        if (epoch_cnt == epochs - 1) {
          epoch_cnt = 0;
          stat_epoch_done = true;
          stat_done = true;
          break;
        } else {
          epoch_cnt++;
        }
      } else {
        batch_cnt++;
      }
    }

    stat_busy = false;
  }
};
