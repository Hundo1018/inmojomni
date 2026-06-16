"""Queries are implemented as `matching1/2/3` on each `StorageBackend` (see
`storage.mojo`, `sparse_backend.mojo`, `archetype.mojo`) and surfaced as
`World.query1/2/3`. The sparse-set backend intersects the smallest component
set; the archetype backend walks the columns of matching archetypes. Both return
`List[Entity]`; iterate it and read/write components via `World.get`/`set`.

This module is intentionally empty — kept as the documented home of the query
design for readers following the package layout.
"""
