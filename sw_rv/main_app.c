void vAccelTask(void* arg);
void vCommTask(void* arg);

int main(void){
  uart_init(0x40000000);
  timer_init(0x40001000, 100000); // 1kHz
  accel_init(0x40002000);

  xTaskCreate(vAccelTask, "ACC", 1024, NULL, tskIDLE_PRIORITY+2, NULL);
  xTaskCreate(vCommTask,  "COM",  768, NULL, tskIDLE_PRIORITY+1, NULL);
  vTaskStartScheduler();
  for(;;);
}

void vAccelTask(void* arg){
  for(;;){
    // write FRAME_LEN, dims, scale, seed...
    ACCEL->FRAME_LEN = 256;
    ACCEL->I_DIM = 256; ACCEL->H_DIM = 64; ACCEL->K_DIM = 10;
    ACCEL->SCALE_SHIFT = 10; ACCEL->RNG_SEED = 0xACE1;
    // load one frame to AXIS-S FIFO (memory-mapped window or IO port)
    axis_write_frame(test_frame, 256);
    ACCEL->CONTROL = ACCEL_CTRL_START;
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    axis_read_logits(logits, 10);
    printf("argmax=%d\r\n", argmax(logits,10));
  }
}
