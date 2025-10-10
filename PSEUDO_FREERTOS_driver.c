// Pseudocode
void vAccelTask(void* arg) {
  for(;;) {
    // Wait frame_ready (from AudioInTask or PS)
    load_frame_to_axis();               // write to AXIS-S FIFO
    rbm_regs->CONTROL = CTRL_START;
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY); // ISR on DONE sets notify
    read_logits_from_axis();            // AXIS-M
    send_result_to_ps();                // mailbox or UART
  }
}

void AccelDoneISR() {
  BaseType_t xHigherPriorityTaskWoken = pdFALSE;
  xTaskNotifyFromISR(accelTaskHandle, 1, eSetValueWithOverwrite, &xHigherPriorityTaskWoken);
  portYIELD_FROM_ISR( xHigherPriorityTaskWoken );
}
