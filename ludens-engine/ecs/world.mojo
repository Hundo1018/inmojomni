from .component import ComponentType
from .entity import Entity

struct World[*CTs: ComponentType]():#FIXME: VariadicList is homogeneous
    """
    CTs: The Components will used for this world.
    """

    alias CTS = VariadicList(CTs) 
    var entities: List[Entity]
    # var components: List[Self.CTS.IterType]
    var counter: UInt64

    fn __init__(out self):
        self.entities = List[Entity]()
        self.counter = 0
        
        # var components = List[Self.CTS.IterType]()


    fn add_entity[*CTs: ComponentType](mut self,owned *c: *CTs):
        entity = Entity(self.counter,self.counter)
        self.counter += 1
        self.entities.append(entity)

    # fn query[*CTs: ComponentType](mut self) -> Query:
    # return Query()
    # fn query(mut self) -> Query:
    #     return Query(len(self.entities))