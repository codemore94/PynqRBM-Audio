#!/usr/bin/env python3
import argparse
import os
import sys
from pathlib import Path


def get_runner_factory():
    try:
        from cocotb_tools.runner import get_runner  # type: ignore
        return get_runner
    except ImportError:
        from cocotb.runner import get_runner  # type: ignore
        return get_runner


def main() -> int:
    parser = argparse.ArgumentParser(description="Run tiny_attn_top_axi cocotb tests.")
    parser.add_argument("--sim", default=os.environ.get("SIM", "modelsim"))
    parser.add_argument("--gui", action="store_true")
    args = parser.parse_args()

    rtl_dir = Path(__file__).resolve().parent.parent
    get_runner = get_runner_factory()
    runner = get_runner(args.sim)

    sources = [
        rtl_dir / "tiny_attn_ctrl_axi.sv",
        rtl_dir / "tiny_attn_core.sv",
        rtl_dir / "tiny_attn_top_axi.sv",
    ]

    runner.build(
        sources=[str(src) for src in sources],
        hdl_toplevel="tiny_attn_top_axi",
        build_dir=str(rtl_dir / "sim_build" / "tiny_attn_cocotb"),
        always=True,
        waves=args.gui,
    )

    runner.test(
        hdl_toplevel="tiny_attn_top_axi",
        test_module="tests.test_tiny_attn_cocotb",
        plusargs=[],
        gui=args.gui,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ImportError as exc:
        print(
            "cocotb is not installed. Install dependencies first, for example:\n"
            "  python3 -m pip install -r requirements-cocotb.txt\n"
            f"Missing import: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)

