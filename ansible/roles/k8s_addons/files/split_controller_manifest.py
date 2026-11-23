#!/usr/bin/env python3
"""Split Envoy Gateway's install.yaml into an idempotent controller manifest and its one-off Job.

install.yaml bundles things that must not be re-applied on every run:
  * CustomResourceDefinitions        -> installed separately (official Gateway API release + EG CRDs)
  * Gateway API admission policies   -> owned by the Gateway API release (*.gateway.networking.k8s.io)
  * the certgen Job                  -> deletes itself after 30s (ttlSecondsAfterFinished), so it is
                                        written to its own file and only run when its Secret is missing

Usage: split_controller_manifest.py <install.yaml> <controller.yaml> <certgen-job.yaml>
"""
import sys

import yaml


def is_gateway_api_bundle(doc: dict) -> bool:
    return doc["kind"] == "CustomResourceDefinition" or doc["metadata"]["name"].endswith(".gateway.networking.k8s.io")


def main(src: str, controller_out: str, job_out: str) -> None:
    with open(src, encoding="utf-8") as f:
        docs = [d for d in yaml.safe_load_all(f) if d]
    kept = [d for d in docs if not is_gateway_api_bundle(d)]
    jobs = [d for d in kept if d["kind"] == "Job"]
    controller = [d for d in kept if d["kind"] != "Job"]

    for path, objects in ((controller_out, controller), (job_out, jobs)):
        with open(path, "w", encoding="utf-8") as f:
            yaml.safe_dump_all(objects, f, sort_keys=False)
    print(f"controller: {len(controller)} objects, jobs: {len(jobs)}, dropped: {len(docs) - len(kept)}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
