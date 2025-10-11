void trainer_start_epoch(uint32_t n_frames, uint16_t batch, uint16_t epochs) {
  REG(BATCH_SIZE)=batch; REG(EPOCHS)=epochs;
  REG(DATA_BASE_LO)=TRAIN_BASE_LO; REG(DATA_BASE_HI)=TRAIN_BASE_HI;
  REG(W_BASE_LO)=W_BASE_LO; REG(W_BASE_HI)=W_BASE_HI;
  REG(LR_MOM)= (MOM<<16) | LR; REG(WEIGHT_DECAY)=WD;
  REG(ACCUM_CTRL)= (1<<0)|(1<<1); // clear pos/neg
  REG(CONTROL)= (1<<1);           // soft reset
  REG(CONTROL)= (1<<0) | (1<<2);  // START + MODE=TRAIN
}

void vTrainerTask(void*){
  trainer_start_epoch(N_FRAMES, 64, 1);
  for(;;){
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY); // ISR notifies on BATCH/EPOCH
    uint32_t st = REG(STATUS);
    if (st & (1<<3)) printf("batch done\r\n");
    if (st & (1<<4)) { printf("epoch done\r\n"); break; }
    if (st & (1<<2)) printf("error!\r\n");
  }
}
