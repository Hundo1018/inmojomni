def est():
    pass


# fn context_switch(old_stack_ptr: Pointer, new_stack_ptr: Pointer):
#     var a = __mlir_op.`llvm.inline_asm`[
#         asm_string="""
#             addi sp, sp, -64
#             sw ra, 60(sp)

#             ret
#         """,
#         constraints="r,r,~{memory}",
#         has_side_effects=True,
#     ](old_stack_ptr, new_stack_ptr)
