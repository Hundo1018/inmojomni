; ModuleID = 'main.mojo'
source_filename = "main.mojo"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@static_string_a61c3395ab9379d9 = internal constant [8 x i8] c"Runtime\00", align 16

define internal ptr @main_closure_0() #0 {
  %1 = call ptr @KGEN_CompilerRT_AsyncRT_CreateRuntime(i64 0)
  ret ptr %1
}

define internal void @main_closure_1(ptr noundef %0) #0 {
  call void @KGEN_CompilerRT_AsyncRT_DestroyRuntime(ptr %0)
  ret void
}

define dso_local i32 @main(i32 noundef %0, ptr noundef %1) #0 {
  %3 = call ptr @KGEN_CompilerRT_AsyncRT_GetCurrentRuntime()
  %4 = ptrtoint ptr %3 to i64
  %5 = icmp ne i64 %4, 0
  br i1 %5, label %6, label %7

6:                                                ; preds = %2
  br label %9

7:                                                ; preds = %2
  %8 = call ptr @KGEN_CompilerRT_GetOrCreateGlobal({ ptr, i64 } { ptr @static_string_a61c3395ab9379d9, i64 7 }, ptr @main_closure_0, ptr @main_closure_1)
  br label %9

9:                                                ; preds = %6, %7
  call void @KGEN_CompilerRT_SetArgV(i32 %0, ptr %1)
  call void @KGEN_CompilerRT_PrintStackTraceOnFault()
  call void @KGEN_CompilerRT_DestroyGlobals()
  ret i32 0
}

declare ptr @KGEN_CompilerRT_AsyncRT_CreateRuntime(i64) #0

declare void @KGEN_CompilerRT_AsyncRT_DestroyRuntime(ptr) #0

declare ptr @KGEN_CompilerRT_AsyncRT_GetCurrentRuntime() #0

declare ptr @KGEN_CompilerRT_GetOrCreateGlobal({ ptr, i64 }, ptr, ptr) #0

declare void @KGEN_CompilerRT_SetArgV(i32, ptr) #0

declare void @KGEN_CompilerRT_PrintStackTraceOnFault() #0

declare void @KGEN_CompilerRT_DestroyGlobals() #0

attributes #0 = { "target-cpu"="skylake" "target-features"="+adx,+aes,+avx,+avx2,+bmi,+bmi2,+clflushopt,+cmov,+crc32,+cx16,+cx8,+f16c,+fma,+fsgsbase,+fxsr,+invpcid,+lzcnt,+mmx,+movbe,+pclmul,+popcnt,+prfchw,+rdrnd,+rdseed,+sahf,+sgx,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+ssse3,+x87,+xsave,+xsavec,+xsaveopt,+xsaves" }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
