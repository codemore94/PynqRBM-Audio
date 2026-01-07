#include <stdint.h>
#include <stdio.h>
#include "FreeRTOS.h"
#include "task.h"

#define UART_BASE 0x40000000u
#define UART_TXD  (*(volatile uint32_t*)(UART_BASE + 0x0))
#define UART_STS  (*(volatile uint32_t*)(UART_BASE + 0x8)) // bit3=TX full

static void putc_uart(char c){
  while (UART_STS & (1<<3)) {}
  UART_TXD = (uint32_t)c;
}
static void puts_uart(const char* s){ while(*s) putc_uart(*s++); }

#define ACCEL_BASE 0x40002000u
#define REG(off)   (*(volatile uint32_t*)(ACCEL_BASE + (off)))

void vHelloTask(void*){
  for(;;){
    puts_uart("Hello from FreeRTOS on PicoRV32!\r\n");
    vTaskDelay(pdMS_TO_TICKS(1000));
  }
}

void vKickRBMTask(void*){
  // Minimal: write dims & start once every 2s
  REG(0x08)=256;  // I_DIM
  REG(0x0C)=64;   // H_DIM (for min core we just compute one column, still okay)
  REG(0x14)=256;  // FRAME_LEN (not used by min core)
  REG(0x18)=10;   // SCALE_SHIFT
  for(;;){
    REG(0x00)=1; // CONTROL.START
    vTaskDelay(pdMS_TO_TICKS(2000));
  }
}

int main(void){
  // Bring up tick timer
  extern void vPortSetupTimerInterrupt(void);
  vPortSetupTimerInterrupt();

  xTaskCreate(vHelloTask, "HELLO", 512, NULL, tskIDLE_PRIORITY+1, NULL);
  xTaskCreate(vKickRBMTask, "RBM",   512, NULL, tskIDLE_PRIORITY+2, NULL);
  vTaskStartScheduler();
  for(;;);
}
