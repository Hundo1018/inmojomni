@register_passable('trivial')
struct Entity:
    var entity_id: UInt64
    var tag:UInt64
    fn __init__(out self, entity_id:UInt64, tag:UInt64):
        self.entity_id = entity_id
        self.tag = tag