from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "verify-in-ubuntu-docker.sh"


def write_verify_config(path: Path) -> None:
    path.write_text(
        yaml.safe_dump(
            {
                "archive": {
                    "suite": "noble",
                    "component": "main",
                    "key_name": "safelibs",
                },
                "repositories": [
                    {
                        "name": "demo",
                        "verify_packages": ["libjson-c5", "libpng16-16t64"],
                    }
                ],
            }
        )
    )


def write_fake_docker(path: Path) -> None:
    path.write_text(
        """#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

Path(os.environ["DOCKER_ARGS_CAPTURE"]).write_text(json.dumps(sys.argv[1:]))
"""
    )
    path.chmod(0o755)


class VerifyInUbuntuDockerTests(unittest.TestCase):
    def test_remote_mode_uses_structured_docker_env_without_setup_script(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config_path = tmp_path / "repositories.yml"
            capture_path = tmp_path / "docker-args.json"
            injected_path = tmp_path / "should-not-exist"
            bin_dir = tmp_path / "bin"
            docker_path = bin_dir / "docker"

            write_verify_config(config_path)
            bin_dir.mkdir()
            write_fake_docker(docker_path)

            repo_target = f"https://example.invalid/$(touch {injected_path})"
            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"
            env["DOCKER_ARGS_CAPTURE"] = str(capture_path)

            subprocess.run(
                ["bash", str(SCRIPT_PATH), repo_target, str(config_path)],
                check=True,
                cwd=REPO_ROOT,
                env=env,
            )

            self.assertFalse(
                injected_path.exists(),
                "malicious shell content in the remote URL must not execute on the host",
            )

            docker_args = json.loads(capture_path.read_text())
            docker_env: dict[str, str] = {}
            idx = 0
            while idx < len(docker_args):
                if docker_args[idx] == "-e":
                    name, value = docker_args[idx + 1].split("=", 1)
                    docker_env[name] = value
                    idx += 2
                    continue
                idx += 1

            self.assertEqual(docker_env["SAFEAPTREPO_VERIFY_MODE"], "remote")
            self.assertEqual(docker_env["SAFEAPTREPO_VERIFY_REPO_URI"], repo_target)
            self.assertEqual(docker_env["SAFEAPTREPO_VERIFY_KEY_NAME"], "safelibs")
            self.assertEqual(docker_env["SAFEAPTREPO_VERIFY_SUITE"], "noble")
            self.assertEqual(docker_env["SAFEAPTREPO_VERIFY_COMPONENT"], "main")
            self.assertNotIn("SAFEAPTREPO_VERIFY_SETUP", docker_env)
            self.assertNotIn("SAFEDEBREPO_VERIFY_SETUP", docker_env)
