"""Standalone observability pipeline check.

Configures Agent 365 observability with a stub token resolver, attaches an
in-memory exporter alongside the real one, emits a span carrying
`gen_ai.operation.name=chat` inside a `BaggageBuilder` scope, then reports the
final span attributes and what the eligibility filter decides.

Run from repo root:
    .venv/Scripts/python.exe scripts/inspect_observability.py
"""

from __future__ import annotations

import logging
import sys

from opentelemetry import trace
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import (
    InMemorySpanExporter,
)

from microsoft_agents_a365.observability.core.config import configure
from microsoft_agents_a365.observability.core.constants import (
    GEN_AI_AGENT_ID_KEY,
    GEN_AI_OPERATION_NAME_KEY,
    TENANT_ID_KEY,
)
from microsoft_agents_a365.observability.core.exporters.utils import (
    filter_and_partition_by_identity,
)
from microsoft_agents_a365.observability.core.middleware.baggage_builder import (
    BaggageBuilder,
)


logging.basicConfig(level=logging.DEBUG, format="%(levelname)s %(name)s: %(message)s")


def main() -> int:
    status = configure(
        service_name="inspect-obs",
        service_namespace="agent365-samples",
        token_resolver=lambda agent_id, tenant_id: "fake-token",
    )
    if not status:
        print("configure() returned False — observability not initialized")
        return 1

    provider = trace.get_tracer_provider()
    in_mem = InMemorySpanExporter()
    provider.add_span_processor(SimpleSpanProcessor(in_mem))

    tenant_id = "11111111-2222-3333-4444-555555555555"
    agent_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    tracer = trace.get_tracer("inspect-obs")
    with BaggageBuilder().tenant_id(tenant_id).agent_id(agent_id).build():
        with tracer.start_as_current_span(
            "chat gpt-4o-mini",
            attributes={GEN_AI_OPERATION_NAME_KEY: "chat"},
        ):
            pass

    spans = in_mem.get_finished_spans()
    print(f"\n--- Captured {len(spans)} span(s) ---")
    for sp in spans:
        attrs = dict(sp.attributes or {})
        print(f"  name             = {sp.name}")
        print(f"  operation.name   = {attrs.get(GEN_AI_OPERATION_NAME_KEY)}")
        print(f"  tenant.id        = {attrs.get(TENANT_ID_KEY)}")
        print(f"  agent.id         = {attrs.get(GEN_AI_AGENT_ID_KEY)}")

    groups = filter_and_partition_by_identity(spans)
    print(f"\nEligibility filter: {len(groups)} group(s) would be exported")
    for key, items in groups.items():
        print(f"  group {key}: {len(items)} span(s)")

    return 0 if groups else 2


if __name__ == "__main__":
    sys.exit(main())
