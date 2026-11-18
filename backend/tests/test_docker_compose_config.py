"""Regression checks for the Docker Compose host-port exposure boundary."""

import json
import os
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
COMPOSE_FILE = ROOT / "docker-compose.yml"


class DockerComposeBindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.docker = shutil.which("docker")
        if cls.docker is None:
            if os.environ.get("GITHUB_ACTIONS", "").lower() == "true":
                raise RuntimeError("Docker CLI is required in GitHub Actions for Compose config tests.")
            raise unittest.SkipTest("Docker CLI is unavailable; Compose config integration tests were not run.")

    def resolved_api_port(self, bind_address=None, *, set_empty=False):
        env = os.environ.copy()
        env.pop("SMARTSTOCK_BIND_ADDRESS", None)
        if bind_address is not None:
            env["SMARTSTOCK_BIND_ADDRESS"] = bind_address
        elif set_empty:
            env["SMARTSTOCK_BIND_ADDRESS"] = ""
        env.setdefault("SMARTSTOCK_ENV", "development")
        env.setdefault("SMARTSTOCK_API_TOKEN", "")
        result = subprocess.run(
            [
                self.docker,
                "compose",
                "--file",
                str(COMPOSE_FILE),
                "config",
                "--format",
                "json",
            ],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            0,
            msg=f"docker compose config failed: {result.stderr}",
        )
        config = json.loads(result.stdout)
        ports = config["services"]["api"]["ports"]
        self.assertEqual(len(ports), 1)
        return ports[0]

    def test_default_host_binding_is_loopback(self):
        port = self.resolved_api_port()
        self.assertEqual(port["host_ip"], "127.0.0.1")
        self.assertEqual(str(port["published"]), "8000")
        self.assertEqual(port["target"], 8000)

    def test_empty_host_binding_uses_loopback_default(self):
        port = self.resolved_api_port(set_empty=True)
        self.assertEqual(port["host_ip"], "127.0.0.1")
        self.assertEqual(str(port["published"]), "8000")
        self.assertEqual(port["target"], 8000)

    def test_explicit_opt_in_binds_only_the_requested_host_address(self):
        port = self.resolved_api_port("192.0.2.10")
        self.assertEqual(port["host_ip"], "192.0.2.10")
        self.assertEqual(str(port["published"]), "8000")
        self.assertEqual(port["target"], 8000)


if __name__ == "__main__":
    unittest.main()
