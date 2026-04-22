import cocotb

from .tiny_attn_driver import (
    ADAPT_ROW_BIAS,
    ADAPT_ROW_GAIN,
    REG_HW_VERSION,
    REG_PERF_CYCLES,
    REG_PERF_MACS,
    TINY_CTRL_MODE_FULL_BP,
    TINY_CTRL_MODE_TRAIN,
    TINY_CTRL_USE_OUT_PROJ,
    TINY_HW_VERSION,
    TINY_MEMSEL_ADAPT,
    TINY_MEMSEL_ATTN,
    TINY_MEMSEL_OUT,
    TINY_MEMSEL_WK,
    TINY_MEMSEL_WO,
    TINY_MEMSEL_WQ,
    TINY_MEMSEL_WV,
    TinyAttnDriver,
    addr2d,
    s16,
)


@cocotb.test()
async def tiny_attention_inference_and_training(dut):
    drv = TinyAttnDriver(dut)
    await drv.start_clock_and_reset()

    hw_version = await drv.reg_read(REG_HW_VERSION)
    assert hw_version == TINY_HW_VERSION

    await drv.load_identity_case(with_out_proj=False)
    await drv.run_once()

    out00_before = s16(await drv.mem_read(TINY_MEMSEL_OUT, addr2d(0, 0)))
    out01_before = s16(await drv.mem_read(TINY_MEMSEL_OUT, addr2d(0, 1)))
    out10_before = s16(await drv.mem_read(TINY_MEMSEL_OUT, addr2d(1, 0)))
    out11_before = s16(await drv.mem_read(TINY_MEMSEL_OUT, addr2d(1, 1)))

    assert out00_before == 2
    assert out01_before == 1
    assert out10_before == 1
    assert out11_before == 2

    attn00 = await drv.mem_read(TINY_MEMSEL_ATTN, addr2d(0, 0))
    attn01 = await drv.mem_read(TINY_MEMSEL_ATTN, addr2d(0, 1))
    assert (attn00 & 0xFFFF) == 11
    assert (attn01 & 0xFFFF) == 7

    perf_cycles = await drv.reg_read(REG_PERF_CYCLES)
    perf_macs = await drv.reg_read(REG_PERF_MACS)
    assert perf_cycles > 0
    assert perf_macs > 0

    await drv.mem_write(TINY_MEMSEL_ADAPT, addr2d(0, 0), 6)
    await drv.mem_write(TINY_MEMSEL_ADAPT, addr2d(0, 1), 3)
    await drv.mem_write(TINY_MEMSEL_ADAPT, addr2d(1, 0), 3)
    await drv.mem_write(TINY_MEMSEL_ADAPT, addr2d(1, 1), 6)
    await drv.run_once(TINY_CTRL_MODE_TRAIN)

    gain0_after = s16(await drv.mem_read(TINY_MEMSEL_ADAPT, addr2d(ADAPT_ROW_GAIN, 0)))
    bias0_after = s16(await drv.mem_read(TINY_MEMSEL_ADAPT, addr2d(ADAPT_ROW_BIAS, 0)))
    assert gain0_after > 256
    assert bias0_after > 0

    await drv.run_once()
    assert s16(await drv.mem_read(TINY_MEMSEL_OUT, addr2d(0, 0))) > out00_before
    assert s16(await drv.mem_read(TINY_MEMSEL_OUT, addr2d(0, 1))) > out01_before
    assert s16(await drv.mem_read(TINY_MEMSEL_OUT, addr2d(1, 0))) > out10_before
    assert s16(await drv.mem_read(TINY_MEMSEL_OUT, addr2d(1, 1))) > out11_before

    await drv.load_identity_case(with_out_proj=True)
    await drv.mem_write(TINY_MEMSEL_ADAPT, addr2d(0, 0), 6)
    await drv.mem_write(TINY_MEMSEL_ADAPT, addr2d(0, 1), 3)
    await drv.mem_write(TINY_MEMSEL_ADAPT, addr2d(1, 0), 3)
    await drv.mem_write(TINY_MEMSEL_ADAPT, addr2d(1, 1), 6)

    await drv.run_once(TINY_CTRL_USE_OUT_PROJ)
    fullbp_out00_before = s16(await drv.mem_read(TINY_MEMSEL_OUT, addr2d(0, 0)))

    for _ in range(16):
        await drv.run_once(TINY_CTRL_MODE_TRAIN | TINY_CTRL_USE_OUT_PROJ | TINY_CTRL_MODE_FULL_BP)

    wq00_after = await drv.mem_read(TINY_MEMSEL_WQ, addr2d(0, 0))
    wk00_after = await drv.mem_read(TINY_MEMSEL_WK, addr2d(0, 0))
    wv00_after = await drv.mem_read(TINY_MEMSEL_WV, addr2d(0, 0))
    wo00_after = await drv.mem_read(TINY_MEMSEL_WO, addr2d(0, 0))
    assert not (
        (wq00_after & 0xFF) == 1
        and (wk00_after & 0xFF) == 1
        and (wv00_after & 0xFF) == 1
        and (wo00_after & 0xFF) == 1
    )

    await drv.run_once(TINY_CTRL_USE_OUT_PROJ)
    fullbp_out00_after = s16(await drv.mem_read(TINY_MEMSEL_OUT, addr2d(0, 0)))
    assert fullbp_out00_after > fullbp_out00_before

