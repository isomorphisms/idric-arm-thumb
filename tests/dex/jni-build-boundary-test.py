#!/usr/bin/env python3
"""Exercise build-script control flow with a mock NDK, not Android compilation."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = Path(__file__).resolve().parents[2]
TARGETS = {
    "armeabi-v7a": "armv7a-linux-androideabi",
    "arm64-v8a": "aarch64-linux-android",
    "x86_64": "x86_64-linux-android",
    "x86": "i686-linux-android",
}
SYMBOLS = {
    "reddit": ["Java_org_isomorphisms_reddit_RedditCli_run"],
    "wegert": [
        "Java_org_isomorphisms_wegert_WegertActivity_jniProbe",
        "ANativeActivity_onCreate",
    ],
}
MOCK_CLANG = '''import os
from pathlib import Path
import sys

if os.environ.get("JNI_TEST_COMPILER_FAIL") == "1":
    sys.exit(23)
output = Path(sys.argv[sys.argv.index("-o") + 1])
output.write_text("Mock compiler output; not an Android ELF library.\\n")
'''
MOCK_READELF = '''import os
from pathlib import Path
import sys

assert sys.argv[1] == "-Ws"
assert Path(sys.argv[2]).is_file()
marker = Path(os.environ["JNI_TEST_READ_MARKER"])
marker.write_text("started\\n")
try:
    for symbol in os.environ["JNI_TEST_SYMBOLS"].split():
        if symbol != os.environ.get("JNI_TEST_OMIT"):
            sys.stdout.write("1: 00001700 39 FUNC GLOBAL DEFAULT 12 " + symbol + "\\n")
    sys.stdout.flush()
    # More than a pipe buffer, after the first match, without timing/sleeps.
    for _ in range(512):
        sys.stdout.write("0: 00000000 0 NOTYPE LOCAL DEFAULT UND filler\\n" * 128)
    sys.stdout.flush()
except BrokenPipeError:
    # LLVM's default SIGPIPE handler uses EX_IOERR (74), not shell status 141.
    os._exit(74)
marker.write_text("complete\\n")
sys.exit(int(os.environ.get("JNI_TEST_READELF_STATUS", "0")))
'''


class JniBuildBoundaryTest(unittest.TestCase):
    def run_build(self, program, abi, *, omit="", compiler_fail=False, readelf_status=0):
        with tempfile.TemporaryDirectory(prefix="jni boundary ") as directory:
            work = Path(directory)
            ndk = work / "ndk"
            ndk_bin = ndk / "toolchains/llvm/prebuilt/linux-x86_64/bin"
            ndk_bin.mkdir(parents=True)
            api = 24 if program == "reddit" else 29
            for name, source in (
                (f"{TARGETS[abi]}{api}-clang", MOCK_CLANG),
                ("llvm-readelf", MOCK_READELF),
            ):
                executable = ndk_bin / name
                executable.write_text(f"#!{sys.executable}\n" + source)
                executable.chmod(0o755)
            marker = work / "readelf-state"
            env = {key: value for key, value in os.environ.items()
                   if not key.startswith(("ANDROID_", "JNI_TEST_"))}
            env.update(
                ANDROID_NDK_HOME=str(ndk),
                ANDROID_ABI=abi,
                JNI_TEST_SYMBOLS=" ".join(SYMBOLS[program]),
                JNI_TEST_OMIT=omit,
                JNI_TEST_COMPILER_FAIL="1" if compiler_fail else "0",
                JNI_TEST_READELF_STATUS=str(readelf_status),
                JNI_TEST_READ_MARKER=str(marker),
            )
            output = work / "output" / "library.so"
            result = subprocess.run(
                ["bash", str(REPO_ROOT / "tests/dex" / program / "build-jni.sh"),
                 str(output)],
                env=env, capture_output=True, text=True, timeout=20,
            )
            state = marker.read_text() if marker.exists() else "not started\n"
            return result, state

    def test_large_symbol_output(self):
        for program in SYMBOLS:
            for abi in TARGETS:
                with self.subTest(program=program, abi=abi):
                    result, state = self.run_build(program, abi)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(state, "complete\n")
                    self.assertIn("JNI ABI", result.stdout)
                    self.assertIn(abi, result.stdout)

    def test_each_required_symbol_is_checked(self):
        for program, symbols in SYMBOLS.items():
            for abi in TARGETS:
                for symbol in symbols:
                    with self.subTest(program=program, abi=abi, symbol=symbol):
                        result, state = self.run_build(program, abi, omit=symbol)
                        self.assertEqual(result.returncode, 1, result.stderr)
                        self.assertEqual(state, "complete\n")
                        self.assertNotIn("JNI ABI", result.stdout)

    def test_compiler_failure_stops_before_readelf(self):
        for program in SYMBOLS:
            for abi in TARGETS:
                with self.subTest(program=program, abi=abi):
                    result, state = self.run_build(program, abi, compiler_fail=True)
                    self.assertEqual(result.returncode, 23, result.stderr)
                    self.assertEqual(state, "not started\n")
                    self.assertNotIn("JNI ABI", result.stdout)

    def test_readelf_failure_is_not_hidden_by_matching_symbols(self):
        for program in SYMBOLS:
            for abi in TARGETS:
                with self.subTest(program=program, abi=abi):
                    result, state = self.run_build(program, abi, readelf_status=74)
                    self.assertEqual(result.returncode, 74, result.stderr)
                    self.assertEqual(state, "complete\n")
                    self.assertNotIn("JNI ABI", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
