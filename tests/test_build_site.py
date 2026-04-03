from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools import build_site


def make_deb(root: Path, package: str, version: str) -> Path:
    pkg_root = root / package
    (pkg_root / "DEBIAN").mkdir(parents=True)
    (pkg_root / "usr/share/doc" / package).mkdir(parents=True)
    (pkg_root / "usr/share/doc" / package / "README").write_text("ok\n")
    (pkg_root / "DEBIAN" / "control").write_text(
        "\n".join(
            [
                f"Package: {package}",
                f"Version: {version}",
                "Section: libs",
                "Priority: optional",
                "Architecture: amd64",
                "Maintainer: SafeLibs <test@safelibs.invalid>",
                "Description: test package",
                "",
            ]
        )
    )
    deb_path = root / f"{package}_{version}_amd64.deb"
    subprocess.run(["dpkg-deb", "--build", str(pkg_root), str(deb_path)], check=True)
    return deb_path


class BuildSiteTests(unittest.TestCase):
    def test_build_repo_checkout_artifacts_mode(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source_dir = tmp_path / "source"
            artifact_root = tmp_path / "artifacts"
            source_dir.mkdir()
            artifact_root.mkdir()
            deb_path = make_deb(source_dir, "libgamma1", "3.0+safelibs1")

            artifacts = build_site.build_repo(
                {
                    "name": "libgamma",
                    "build": {
                        "mode": "checkout-artifacts",
                        "workdir": ".",
                        "artifact_globs": ["*.deb"],
                    },
                },
                source_dir,
                artifact_root,
                "debian:trixie-slim",
                [],
            )

            self.assertEqual([path.name for path in artifacts], [deb_path.name])
            self.assertTrue((artifact_root / "libgamma" / deb_path.name).exists())

    def test_generate_site_from_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            deb_a = make_deb(tmp_path, "libalpha1", "1.0+safelibs1")
            deb_b = make_deb(tmp_path, "libbeta1", "2.0+safelibs1")
            output_dir = tmp_path / "site"
            template_path = Path(__file__).resolve().parent.parent / "templates" / "index.html"
            config = {
                "archive": {
                    "suite": "stable",
                    "component": "main",
                    "origin": "SafeLibs",
                    "label": "SafeLibs",
                    "description": "Test repo",
                    "homepage": "https://example.invalid/project",
                    "base_url": "https://example.invalid/repo/",
                    "key_name": "safelibs",
                }
            }

            infos = build_site.generate_site_from_artifacts(
                config,
                [deb_a, deb_b],
                output_dir,
                template_path=template_path,
                base_url="https://example.invalid/repo/",
            )

            self.assertEqual([info.name for info in infos], ["libalpha1", "libbeta1"])
            self.assertTrue((output_dir / "index.html").exists())
            self.assertTrue((output_dir / "safelibs.asc").exists())
            self.assertTrue((output_dir / "safelibs.gpg").exists())
            self.assertTrue((output_dir / "safelibs.pref").exists())
            self.assertTrue((output_dir / "dists/stable/InRelease").exists())
            packages_text = (output_dir / "dists/stable/main/binary-amd64/Packages").read_text()
            self.assertIn("Package: libalpha1", packages_text)
            self.assertIn("Package: libbeta1", packages_text)
            self.assertIn("\n\nPackage: libbeta1", packages_text)
            release_text = (output_dir / "dists/stable/Release").read_text()
            self.assertIn("Origin: SafeLibs", release_text)
            pref_text = (output_dir / "safelibs.pref").read_text()
            self.assertIn("Package: libalpha1 libbeta1", pref_text)
            self.assertIn("Pin: release o=SafeLibs", pref_text)
            self.assertIn("Pin-Priority: 1001", pref_text)

    def test_split_stanzas_discards_empty_chunks(self) -> None:
        raw = "Package: a\nArchitecture: amd64\n\nPackage: b\nArchitecture: amd64\n\n"
        stanzas = build_site.split_stanzas(raw)
        self.assertEqual(len(stanzas), 2)
        self.assertTrue(stanzas[0].startswith("Package: a"))


if __name__ == "__main__":
    unittest.main()
