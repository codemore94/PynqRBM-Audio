from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from .axi_lite import AxiLiteMaster


REG_CONTROL = 0x00
REG_STATUS = 0x04
REG_SEQ_LEN = 0x08
REG_D_MODEL = 0x0C
REG_D_HEAD = 0x10
REG_SCORE_SHIFT = 0x14
REG_NORM_BIAS = 0x18
REG_HW_VERSION = 0x40
REG_PERF_CYCLES = 0x44
REG_PERF_MACS = 0x48
REG_MEM_ADDR = 0x54
REG_MEM_WDATA = 0x58
REG_MEM_RDATA = 0x5C
REG_MEM_CTRL = 0x60

TINY_HW_VERSION = 0x0001_1000
TINY_STATUS_DONE = 1 << 1
TINY_STATUS_ERR = 1 << 2

TINY_CTRL_START = 1 << 0
TINY_CTRL_SOFT_RST = 1 << 1
TINY_CTRL_MODE_TRAIN = 1 << 2
TINY_CTRL_USE_OUT_PROJ = 1 << 3
TINY_CTRL_CAUSAL = 1 << 4
TINY_CTRL_MODE_FULL_BP = 1 << 5

TINY_MEMSEL_TOKEN = 0
TINY_MEMSEL_WQ = 1
TINY_MEMSEL_WK = 2
TINY_MEMSEL_WV = 3
TINY_MEMSEL_WO = 4
TINY_MEMSEL_OUT = 5
TINY_MEMSEL_ATTN = 6
TINY_MEMSEL_ADAPT = 7

ADAPT_ROW_GAIN = 0xFFFE
ADAPT_ROW_BIAS = 0xFFFF


def addr2d(row: int, col: int) -> int:
    return ((row & 0xFFFF) << 16) | (col & 0xFFFF)


def s16(value: int) -> int:
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


class TinyAttnDriver:
    def __init__(self, dut):
        self.dut = dut
        self.axi = AxiLiteMaster(dut)

    async def start_clock_and_reset(self) -> None:
        self.axi.set_idle()
        self.dut.ARESETn.value = 0
        cocotb_clock = Clock(self.dut.ACLK, 10, units="ns")
        cocotb.start_soon(cocotb_clock.start())
        for _ in range(5):
            await RisingEdge(self.dut.ACLK)
        self.dut.ARESETn.value = 1
        for _ in range(5):
            await RisingEdge(self.dut.ACLK)

    async def reg_write(self, addr: int, data: int) -> None:
        await self.axi.write(addr, data)

    async def reg_read(self, addr: int) -> int:
        return await self.axi.read(addr)

    async def mem_write(self, sel: int, addr: int, data: int) -> None:
        await self.reg_write(REG_MEM_CTRL, sel & 0x7)
        await self.reg_write(REG_MEM_ADDR, addr)
        await self.reg_write(REG_MEM_WDATA, data)

    async def mem_read(self, sel: int, addr: int) -> int:
        await self.reg_write(REG_MEM_CTRL, sel & 0x7)
        await self.reg_write(REG_MEM_ADDR, addr)
        return await self.reg_read(REG_MEM_RDATA)

    async def wait_done(self, timeout_cycles: int = 6000) -> int:
        status = 0
        for _ in range(timeout_cycles):
            status = await self.reg_read(REG_STATUS)
            if status & TINY_STATUS_DONE:
                return status
            if status & TINY_STATUS_ERR:
                raise AssertionError(f"unexpected ERR status 0x{status:08x}")
            await RisingEdge(self.dut.ACLK)
        raise AssertionError("timeout waiting for DONE")

    async def load_identity_case(self, with_out_proj: bool = False) -> None:
        await self.reg_write(REG_CONTROL, TINY_CTRL_SOFT_RST)
        await self.reg_write(REG_CONTROL, 0)
        await self.reg_write(REG_SEQ_LEN, 2)
        await self.reg_write(REG_D_MODEL, 2)
        await self.reg_write(REG_D_HEAD, 2)
        await self.reg_write(REG_SCORE_SHIFT, 0)
        await self.reg_write(REG_NORM_BIAS, 1)

        await self.mem_write(TINY_MEMSEL_TOKEN, addr2d(0, 0), 3)
        await self.mem_write(TINY_MEMSEL_TOKEN, addr2d(0, 1), 1)
        await self.mem_write(TINY_MEMSEL_TOKEN, addr2d(1, 0), 1)
        await self.mem_write(TINY_MEMSEL_TOKEN, addr2d(1, 1), 3)

        for r in range(2):
            for sel in (TINY_MEMSEL_WQ, TINY_MEMSEL_WK, TINY_MEMSEL_WV):
                await self.mem_write(sel, addr2d(r, 0), 1 if r == 0 else 0)
                await self.mem_write(sel, addr2d(r, 1), 1 if r == 1 else 0)
            await self.mem_write(TINY_MEMSEL_WO, addr2d(r, 0), 1 if r == 0 else 0)
            await self.mem_write(TINY_MEMSEL_WO, addr2d(r, 1), 1 if r == 1 else 0)

        if with_out_proj:
            await self.reg_write(REG_CONTROL, TINY_CTRL_USE_OUT_PROJ)
        else:
            await self.reg_write(REG_CONTROL, 0)

    async def run_once(self, control_bits: int = 0) -> None:
        await self.reg_write(REG_CONTROL, control_bits | TINY_CTRL_START)
        await self.reg_write(REG_CONTROL, control_bits)
        await self.wait_done()

