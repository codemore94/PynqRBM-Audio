#include <stdint.h>

#include "rbm_regs.h"

#define UART_DIV   (*(volatile uint32_t *)0x10000000u)
#define UART_DATA  (*(volatile uint32_t *)0x10000004u)
#define TIMER_CTRL (*(volatile uint32_t *)0x10001010u)
#define RBM_BASE   0x40000000u

static void uart_putc(char c) {
  while ((UART_DATA & 0x80000000u) == 0u) {
  }
  UART_DATA = (uint32_t)(uint8_t)c;
}

static void uart_puts(const char *s) {
  while (*s) uart_putc(*s++);
}

int main(void) {
  UART_DIV = 100;
  TIMER_CTRL = 0;

  if (rbm_rd(RBM_BASE, RBM_REG_HW_VERSION) != 0x00010000u) {
    uart_puts("rbm version fail\n");
    return 1;
  }

  rbm_wr(RBM_BASE, RBM_REG_I_DIM, 4);
  rbm_wr(RBM_BASE, RBM_REG_H_DIM, 4);
  rbm_wr(RBM_BASE, RBM_REG_LR_MOM, 0x00000100u);
  rbm_wr(RBM_BASE, RBM_REG_CONTROL, RBM_CTRL_DETERM | RBM_CTRL_START);
  rbm_wr(RBM_BASE, RBM_REG_CONTROL, RBM_CTRL_DETERM);
  while ((rbm_rd(RBM_BASE, RBM_REG_STATUS) & RBM_STATUS_DONE) == 0u) {
  }

  uart_puts("rbm done\n");
  return 0;
}
