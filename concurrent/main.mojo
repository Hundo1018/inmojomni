# fn gpio_init(pin: UInt32):
#     # IO_BANK0: funcsel = SIO (5)
#     # ctrl register = IO_BANK0_BASE + 4 + pin * 8
#     # IO_BANK0_BASE = 0x40028000
#     var ctrl_addr_int = UInt32(0x40028004) + pin * 8
#     var ctrl_ptr = __mlir_op.`llvm.inttoptr`[
#         _type=__mlir_type.`!llvm.ptr`
#     ](ctrl_addr_int._mlir_value)  # runtime 位址，需要另外處理

#     # SIO_GPIO_OE_SET = 0xD0000038
#     var oe_ptr = __mlir_op.`llvm.inttoptr`[
#         _type=__mlir_type.`!llvm.ptr`
#     ](__mlir_attr.`0xD0000038 : i32`)

#     var mask = UInt32(1) << pin
#     var mask_i32 = __mlir_op.`pop.cast_to_builtin`[
#         _type=__mlir_type.i32
#     ](mask._mlir_value)

#     __mlir_op.`llvm.store`[
#         _type=None,
#         _properties=__mlir_attr.`{ordering = 0 : i64, isVolatile = true}`,
#     ](mask_i32, oe_ptr)

# def gpio_set(pin: UInt32, val: UInt32):
#     # SIO base = 0xD0000000
#     # OUT_SET offset = 0x018, OUT_CLR offset = 0x01C
#     # 根據 val 選擇寫哪個暫存器
#     var out_set_addr = __mlir_op.`llvm.inttoptr`[_type=__mlir_type.`!llvm.ptr`](
#         __mlir_attr.`0xD0000018 : i32`
#     )

#     var out_clr_addr = __mlir_op.`llvm.inttoptr`[_type=__mlir_type.`!llvm.ptr`](
#         __mlir_attr.`0xD000001C : i32`
#     )

#     # pin mask: 1 << pin
#     var mask = UInt32(1) << pin

#     # cast UInt32 → i32 for llvm.store
#     var mask_i32 = __mlir_op.`pop.cast_to_builtin`[_type=__mlir_type.i32](
#         mask._mlir_value
#     )

#     __mlir_op.`llvm.store`[
#         _type=None,
#         _properties=__mlir_attr.`{ordering = 0 : i64, isVolatile = true}`,
#     ](mask_i32, out_set_addr)
from std.memory import UnsafePointer, alloc

comptime _I32Ptr = type_of(alloc[Int32](1))

def write_to_address(mmio_address: Int, value: Int32):
    var ptr = _I32Ptr(unsafe_from_address=mmio_address)
    # Writing to a raw memory address requires volatile store to prevent the
    # compiler from eliding the access as a dead write.
    ptr.store[volatile=True](value)

def main():
    var ptr = alloc[Int](1)
    
    # var ptr = UnsafePointer(unsafe_from_address=0xD000001C)
    # gpio_set(25, 1)  # GPIO25 高電位
    # gpio_set(25, 0)  # GPIO25 低電位
