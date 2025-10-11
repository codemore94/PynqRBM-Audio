CROSS=riscv32-unknown-elf
CFLAGS=-Os -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib -Wall
LDS=bsp/linker.ld
SRCS=app/main.c


all: app.elf app.bin
app.elf: $(SRCS)
$(CROSS)-gcc $(CFLAGS) -T $(LDS) -o $@ $^
app.bin: app.elf
$(CROSS)-objcopy -O binary $< $@
clean:
rm -f app.elf app.bin
