import cocotb
from cocotb.triggers import RisingEdge


class AxiLiteMaster:
    def __init__(self, dut, prefix: str = "S_"):
        self.dut = dut
        self.awaddr = getattr(dut, f"{prefix}AWADDR")
        self.awvalid = getattr(dut, f"{prefix}AWVALID")
        self.awready = getattr(dut, f"{prefix}AWREADY")
        self.wdata = getattr(dut, f"{prefix}WDATA")
        self.wstrb = getattr(dut, f"{prefix}WSTRB")
        self.wvalid = getattr(dut, f"{prefix}WVALID")
        self.wready = getattr(dut, f"{prefix}WREADY")
        self.bresp = getattr(dut, f"{prefix}BRESP")
        self.bvalid = getattr(dut, f"{prefix}BVALID")
        self.bready = getattr(dut, f"{prefix}BREADY")
        self.araddr = getattr(dut, f"{prefix}ARADDR")
        self.arvalid = getattr(dut, f"{prefix}ARVALID")
        self.arready = getattr(dut, f"{prefix}ARREADY")
        self.rdata = getattr(dut, f"{prefix}RDATA")
        self.rresp = getattr(dut, f"{prefix}RRESP")
        self.rvalid = getattr(dut, f"{prefix}RVALID")
        self.rready = getattr(dut, f"{prefix}RREADY")

    def set_idle(self) -> None:
        self.awaddr.value = 0
        self.awvalid.value = 0
        self.wdata.value = 0
        self.wstrb.value = 0
        self.wvalid.value = 0
        self.bready.value = 0
        self.araddr.value = 0
        self.arvalid.value = 0
        self.rready.value = 0

    async def write(self, addr: int, data: int, wstrb: int = 0xF) -> None:
        await RisingEdge(self.dut.ACLK)
        self.awaddr.value = addr
        self.awvalid.value = 1
        self.wdata.value = data
        self.wstrb.value = wstrb
        self.wvalid.value = 1
        self.bready.value = 1

        while not (int(self.awready.value) and int(self.wready.value)):
            await RisingEdge(self.dut.ACLK)

        await RisingEdge(self.dut.ACLK)
        self.awvalid.value = 0
        self.wvalid.value = 0

        while not int(self.bvalid.value):
            await RisingEdge(self.dut.ACLK)

        await RisingEdge(self.dut.ACLK)
        self.bready.value = 0

    async def read(self, addr: int) -> int:
        await RisingEdge(self.dut.ACLK)
        self.araddr.value = addr
        self.arvalid.value = 1
        self.rready.value = 1

        while not int(self.arready.value):
            await RisingEdge(self.dut.ACLK)

        await RisingEdge(self.dut.ACLK)
        self.arvalid.value = 0

        while not int(self.rvalid.value):
            await RisingEdge(self.dut.ACLK)

        value = int(self.rdata.value)
        await RisingEdge(self.dut.ACLK)
        self.rready.value = 0
        return value

