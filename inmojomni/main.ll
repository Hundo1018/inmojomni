; ModuleID = 'main.mojo'
source_filename = "main.mojo"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@static_string_f226f6c93bcedaf4 = internal constant [2 x i8] c"\1B\00", align 16
@static_string_a61c3395ab9379d9 = internal constant [8 x i8] c"Runtime\00", align 16

define internal void @"main::main()"() #0 {
  %1 = alloca { ptr, i64, i64 }, i64 1, align 8
  %2 = alloca { ptr, i64, i64 }, i64 1, align 8
  call void @llvm.lifetime.end.p0(ptr %2)
  call void @llvm.lifetime.start.p0(ptr %2)
  store { ptr, i64, i64 } { ptr inttoptr (i64 4862299 to ptr), i64 0, i64 -9007199254740992000 }, ptr %2, align 8
  call void @llvm.lifetime.end.p0(ptr %1)
  call void @llvm.lifetime.start.p0(ptr %1)
  %3 = getelementptr { ptr, i64, i64 }, ptr %1, i32 0, i32 1
  store i64 1, ptr %3, align 8
  %4 = getelementptr { ptr, i64, i64 }, ptr %1, i32 0, i32 0
  store ptr @static_string_f226f6c93bcedaf4, ptr %4, align 8
  %5 = getelementptr { ptr, i64, i64 }, ptr %1, i32 0, i32 2
  store i64 2305843009213693952, ptr %5, align 8
  %6 = getelementptr { ptr, i64, i64 }, ptr %2, i32 0, i32 0
  %7 = getelementptr { ptr, i64, i64 }, ptr %2, i32 0, i32 2
  %8 = load i64, ptr %7, align 8
  %9 = and i64 %8, -9223372036854775808
  %10 = icmp ne i64 %9, 0
  br i1 %10, label %11, label %12

11:                                               ; preds = %0
  br label %14

12:                                               ; preds = %0
  %13 = load ptr, ptr %6, align 8
  br label %14

14:                                               ; preds = %11, %12
  %15 = phi ptr [ %13, %12 ], [ %2, %11 ]
  %16 = getelementptr { ptr, i64, i64 }, ptr %2, i32 0, i32 1
  %17 = load i64, ptr %7, align 8
  %18 = and i64 %17, -9223372036854775808
  %19 = icmp ne i64 %18, 0
  br i1 %19, label %20, label %24

20:                                               ; preds = %14
  %21 = load i64, ptr %7, align 8
  %22 = and i64 %21, 2233785415175766016
  %23 = ashr i64 %22, 56
  br label %26

24:                                               ; preds = %14
  %25 = load i64, ptr %16, align 8
  br label %26

26:                                               ; preds = %20, %24
  %27 = phi i64 [ %25, %24 ], [ %23, %20 ]
  %28 = insertvalue { ptr, i64 } undef, ptr %15, 0
  %29 = insertvalue { ptr, i64 } %28, i64 %27, 1
  %30 = load i64, ptr %5, align 8
  %31 = and i64 %30, -9223372036854775808
  %32 = icmp ne i64 %31, 0
  br i1 %32, label %33, label %34

33:                                               ; preds = %26
  br label %36

34:                                               ; preds = %26
  %35 = load ptr, ptr %4, align 8
  br label %36

36:                                               ; preds = %33, %34
  %37 = phi ptr [ %35, %34 ], [ %1, %33 ]
  %38 = load i64, ptr %5, align 8
  %39 = and i64 %38, -9223372036854775808
  %40 = icmp ne i64 %39, 0
  br i1 %40, label %41, label %45

41:                                               ; preds = %36
  %42 = load i64, ptr %5, align 8
  %43 = and i64 %42, 2233785415175766016
  %44 = ashr i64 %43, 56
  br label %47

45:                                               ; preds = %36
  %46 = load i64, ptr %3, align 8
  br label %47

47:                                               ; preds = %41, %45
  %48 = phi i64 [ %46, %45 ], [ %44, %41 ]
  %49 = insertvalue { ptr, i64 } undef, ptr %37, 0
  %50 = insertvalue { ptr, i64 } %49, i64 %48, 1
  %51 = call { ptr, i64, i64 } @"std::collections::string::string::String::_add[::Bool,::Origin[$0],::Bool,::Origin[$2]](::Span[$0, ::SIMD[::DType(uint8), ::Int(1)], $1],::Span[$2, ::SIMD[::DType(uint8), ::Int(1)], $3])_REMOVED_ARG"({ ptr, i64 } %50, { ptr, i64 } %29)
  %52 = extractvalue { ptr, i64, i64 } %51, 0
  %53 = extractvalue { ptr, i64, i64 } %51, 2
  %54 = load i64, ptr %5, align 8
  %55 = and i64 %54, 4611686018427387904
  %56 = icmp ne i64 %55, 0
  br i1 %56, label %57, label %66

57:                                               ; preds = %47
  %58 = load ptr, ptr %4, align 8
  %59 = getelementptr inbounds i8, ptr %58, i32 -8
  %60 = getelementptr { i64 }, ptr %59, i32 0, i32 0
  %61 = atomicrmw sub ptr %60, i64 1 release, align 8
  %62 = icmp eq i64 %61, 1
  br i1 %62, label %63, label %64

63:                                               ; preds = %57
  fence acquire
  call void @KGEN_CompilerRT_AlignedFree(ptr %59)
  br label %65

64:                                               ; preds = %57
  br label %65

65:                                               ; preds = %63, %64
  br label %67

66:                                               ; preds = %47
  br label %67

67:                                               ; preds = %65, %66
  call void @llvm.lifetime.end.p0(ptr %1)
  %68 = and i64 %53, 4611686018427387904
  %69 = icmp ne i64 %68, 0
  br i1 %69, label %70, label %78

70:                                               ; preds = %67
  %71 = getelementptr inbounds i8, ptr %52, i32 -8
  %72 = getelementptr { i64 }, ptr %71, i32 0, i32 0
  %73 = atomicrmw sub ptr %72, i64 1 release, align 8
  %74 = icmp eq i64 %73, 1
  br i1 %74, label %75, label %76

75:                                               ; preds = %70
  fence acquire
  call void @KGEN_CompilerRT_AlignedFree(ptr %71)
  br label %77

76:                                               ; preds = %70
  br label %77

77:                                               ; preds = %75, %76
  br label %79

78:                                               ; preds = %67
  br label %79

79:                                               ; preds = %77, %78
  %80 = load i64, ptr %7, align 8
  %81 = and i64 %80, 4611686018427387904
  %82 = icmp ne i64 %81, 0
  br i1 %82, label %83, label %92

83:                                               ; preds = %79
  %84 = load ptr, ptr %6, align 8
  %85 = getelementptr inbounds i8, ptr %84, i32 -8
  %86 = getelementptr { i64 }, ptr %85, i32 0, i32 0
  %87 = atomicrmw sub ptr %86, i64 1 release, align 8
  %88 = icmp eq i64 %87, 1
  br i1 %88, label %89, label %90

89:                                               ; preds = %83
  fence acquire
  call void @KGEN_CompilerRT_AlignedFree(ptr %85)
  br label %91

90:                                               ; preds = %83
  br label %91

91:                                               ; preds = %89, %90
  br label %93

92:                                               ; preds = %79
  br label %93

93:                                               ; preds = %91, %92
  call void @llvm.lifetime.end.p0(ptr %2)
  ret void
}

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
  call void @"main::main()"()
  call void @KGEN_CompilerRT_DestroyGlobals()
  ret i32 0
}

define internal ptr @"std::collections::string::string::String::unsafe_ptr_mut(::String&,::Int$)"(ptr noalias noundef nonnull %0, i64 noundef %1) #0 {
  %3 = getelementptr { ptr, i64, i64 }, ptr %0, i32 0, i32 0
  %4 = getelementptr { ptr, i64, i64 }, ptr %0, i32 0, i32 1
  %5 = getelementptr { ptr, i64, i64 }, ptr %0, i32 0, i32 2
  %6 = load i64, ptr %5, align 8
  %7 = and i64 %6, -9223372036854775808
  %8 = icmp ne i64 %7, 0
  br i1 %8, label %9, label %10

9:                                                ; preds = %2
  br label %22

10:                                               ; preds = %2
  %11 = load i64, ptr %5, align 8
  %12 = and i64 %11, 4611686018427387904
  %13 = icmp ne i64 %12, 0
  %14 = xor i1 %13, true
  br i1 %14, label %15, label %17

15:                                               ; preds = %10
  %16 = load i64, ptr %4, align 8
  br label %20

17:                                               ; preds = %10
  %18 = load i64, ptr %5, align 8
  %19 = shl i64 %18, 3
  br label %20

20:                                               ; preds = %15, %17
  %21 = phi i64 [ %19, %17 ], [ %16, %15 ]
  br label %22

22:                                               ; preds = %9, %20
  %23 = phi i64 [ %21, %20 ], [ 23, %9 ]
  %24 = call i64 @llvm.smax.i64(i64 %23, i64 %1)
  %25 = icmp sle i64 %24, 23
  br i1 %25, label %26, label %34

26:                                               ; preds = %22
  %27 = load i64, ptr %5, align 8
  %28 = and i64 %27, -9223372036854775808
  %29 = icmp ne i64 %28, 0
  %30 = xor i1 %29, true
  br i1 %30, label %31, label %32

31:                                               ; preds = %26
  tail call void @"std::collections::string::string::String::_inline_string(::String&)"(ptr %0)
  br label %33

32:                                               ; preds = %26
  br label %33

33:                                               ; preds = %31, %32
  br label %74

34:                                               ; preds = %22
  %35 = load i64, ptr %5, align 8
  %36 = and i64 %35, 4611686018427387904
  %37 = icmp ne i64 %36, 0
  br i1 %37, label %38, label %44

38:                                               ; preds = %34
  %39 = load ptr, ptr %3, align 8
  %40 = getelementptr inbounds i8, ptr %39, i32 -8
  %41 = getelementptr { i64 }, ptr %40, i32 0, i32 0
  %42 = load atomic i64, ptr %41 monotonic, align 8
  %43 = icmp eq i64 %42, 1
  br label %45

44:                                               ; preds = %34
  br label %45

45:                                               ; preds = %38, %44
  %46 = phi i1 [ false, %44 ], [ %43, %38 ]
  %47 = xor i1 %46, true
  br i1 %47, label %48, label %49

48:                                               ; preds = %45
  br label %69

49:                                               ; preds = %45
  %50 = load i64, ptr %5, align 8
  %51 = and i64 %50, -9223372036854775808
  %52 = icmp ne i64 %51, 0
  br i1 %52, label %53, label %54

53:                                               ; preds = %49
  br label %66

54:                                               ; preds = %49
  %55 = load i64, ptr %5, align 8
  %56 = and i64 %55, 4611686018427387904
  %57 = icmp ne i64 %56, 0
  %58 = xor i1 %57, true
  br i1 %58, label %59, label %61

59:                                               ; preds = %54
  %60 = load i64, ptr %4, align 8
  br label %64

61:                                               ; preds = %54
  %62 = load i64, ptr %5, align 8
  %63 = shl i64 %62, 3
  br label %64

64:                                               ; preds = %59, %61
  %65 = phi i64 [ %63, %61 ], [ %60, %59 ]
  br label %66

66:                                               ; preds = %53, %64
  %67 = phi i64 [ %65, %64 ], [ 23, %53 ]
  %68 = icmp sgt i64 %24, %67
  br label %69

69:                                               ; preds = %48, %66
  %70 = phi i1 [ %68, %66 ], [ true, %48 ]
  br i1 %70, label %71, label %72

71:                                               ; preds = %69
  tail call void @"std::collections::string::string::String::_realloc_mutable(::String&,::Int)"(ptr %0, i64 %24)
  br label %73

72:                                               ; preds = %69
  br label %73

73:                                               ; preds = %71, %72
  br label %74

74:                                               ; preds = %33, %73
  %75 = load i64, ptr %5, align 8
  %76 = and i64 %75, -9223372036854775808
  %77 = icmp ne i64 %76, 0
  br i1 %77, label %78, label %79

78:                                               ; preds = %74
  br label %81

79:                                               ; preds = %74
  %80 = load ptr, ptr %3, align 8
  br label %81

81:                                               ; preds = %78, %79
  %82 = phi ptr [ %80, %79 ], [ %0, %78 ]
  ret ptr %82
}

define internal void @"std::collections::string::string::String::_inline_string(::String&)"(ptr noalias noundef nonnull %0) #0 {
  %2 = alloca { ptr, i64, i64 }, i64 1, align 8
  %3 = getelementptr { ptr, i64, i64 }, ptr %0, i32 0, i32 0
  %4 = getelementptr { ptr, i64, i64 }, ptr %0, i32 0, i32 1
  %5 = getelementptr { ptr, i64, i64 }, ptr %0, i32 0, i32 2
  %6 = load i64, ptr %5, align 8
  %7 = and i64 %6, -9223372036854775808
  %8 = icmp ne i64 %7, 0
  br i1 %8, label %9, label %13

9:                                                ; preds = %1
  %10 = load i64, ptr %5, align 8
  %11 = and i64 %10, 2233785415175766016
  %12 = ashr i64 %11, 56
  br label %15

13:                                               ; preds = %1
  %14 = load i64, ptr %4, align 8
  br label %15

15:                                               ; preds = %9, %13
  %16 = phi i64 [ %14, %13 ], [ %12, %9 ]
  call void @llvm.lifetime.end.p0(ptr %2)
  call void @llvm.lifetime.start.p0(ptr %2)
  %17 = getelementptr { ptr, i64, i64 }, ptr %2, i32 0, i32 2
  store i64 -9223372036854775808, ptr %17, align 8
  %18 = getelementptr { ptr, i64, i64 }, ptr %2, i32 0, i32 1
  %19 = shl i64 %16, 56
  %20 = load i64, ptr %17, align 8
  %21 = and i64 %20, -9223372036854775808
  %22 = icmp ne i64 %21, 0
  br i1 %22, label %23, label %27

23:                                               ; preds = %15
  %24 = load i64, ptr %17, align 8
  %25 = and i64 %24, -2233785415175766017
  %26 = or i64 %25, %19
  store i64 %26, ptr %17, align 8
  br label %28

27:                                               ; preds = %15
  store i64 %16, ptr %18, align 8
  br label %28

28:                                               ; preds = %23, %27
  %29 = load i64, ptr %5, align 8
  %30 = and i64 %29, -9223372036854775808
  %31 = icmp ne i64 %30, 0
  br i1 %31, label %32, label %33

32:                                               ; preds = %28
  br label %35

33:                                               ; preds = %28
  %34 = load ptr, ptr %3, align 8
  br label %35

35:                                               ; preds = %32, %33
  %36 = phi ptr [ %34, %33 ], [ %0, %32 ]
  %37 = call i64 @llvm.smax.i64(i64 %16, i64 0)
  br label %38

38:                                               ; preds = %43, %35
  %39 = phi i64 [ %37, %35 ], [ %44, %43 ]
  %40 = icmp sgt i64 %39, 0
  br i1 %40, label %41, label %42

41:                                               ; preds = %38
  br label %43

42:                                               ; preds = %38
  br label %49

43:                                               ; preds = %41
  %44 = sub i64 %39, 1
  %45 = sub i64 %37, %39
  %46 = getelementptr inbounds i8, ptr %2, i64 %45
  %47 = getelementptr inbounds i8, ptr %36, i64 %45
  %48 = load i8, ptr %47, align 1
  store i8 %48, ptr %46, align 1
  br label %38

49:                                               ; preds = %42
  %50 = load i64, ptr %5, align 8
  %51 = and i64 %50, 4611686018427387904
  %52 = icmp ne i64 %51, 0
  br i1 %52, label %53, label %62

53:                                               ; preds = %49
  %54 = load ptr, ptr %3, align 8
  %55 = getelementptr inbounds i8, ptr %54, i32 -8
  %56 = getelementptr { i64 }, ptr %55, i32 0, i32 0
  %57 = atomicrmw sub ptr %56, i64 1 release, align 8
  %58 = icmp eq i64 %57, 1
  br i1 %58, label %59, label %60

59:                                               ; preds = %53
  fence acquire
  call void @KGEN_CompilerRT_AlignedFree(ptr %55)
  br label %61

60:                                               ; preds = %53
  br label %61

61:                                               ; preds = %59, %60
  br label %63

62:                                               ; preds = %49
  br label %63

63:                                               ; preds = %61, %62
  %64 = getelementptr { ptr, i64, i64 }, ptr %2, i32 0, i32 0
  %65 = load ptr, ptr %64, align 8
  store ptr %65, ptr %3, align 8
  %66 = load i64, ptr %18, align 8
  store i64 %66, ptr %4, align 8
  %67 = load i64, ptr %17, align 8
  store i64 %67, ptr %5, align 8
  call void @llvm.lifetime.end.p0(ptr %2)
  ret void
}

define internal void @"std::collections::string::string::String::_realloc_mutable(::String&,::Int)"(ptr noalias noundef nonnull %0, i64 noundef %1) #0 {
  %3 = getelementptr { ptr, i64, i64 }, ptr %0, i32 0, i32 0
  %4 = getelementptr { ptr, i64, i64 }, ptr %0, i32 0, i32 1
  %5 = getelementptr { ptr, i64, i64 }, ptr %0, i32 0, i32 2
  %6 = load i64, ptr %5, align 8
  %7 = and i64 %6, -9223372036854775808
  %8 = icmp ne i64 %7, 0
  br i1 %8, label %9, label %13

9:                                                ; preds = %2
  %10 = load i64, ptr %5, align 8
  %11 = and i64 %10, 2233785415175766016
  %12 = ashr i64 %11, 56
  br label %15

13:                                               ; preds = %2
  %14 = load i64, ptr %4, align 8
  br label %15

15:                                               ; preds = %9, %13
  %16 = phi i64 [ %14, %13 ], [ %12, %9 ]
  %17 = load i64, ptr %5, align 8
  %18 = and i64 %17, -9223372036854775808
  %19 = icmp ne i64 %18, 0
  br i1 %19, label %20, label %21

20:                                               ; preds = %15
  br label %23

21:                                               ; preds = %15
  %22 = load ptr, ptr %3, align 8
  br label %23

23:                                               ; preds = %20, %21
  %24 = phi ptr [ %22, %21 ], [ %0, %20 ]
  %25 = load i64, ptr %5, align 8
  %26 = and i64 %25, -9223372036854775808
  %27 = icmp ne i64 %26, 0
  br i1 %27, label %28, label %29

28:                                               ; preds = %23
  br label %41

29:                                               ; preds = %23
  %30 = load i64, ptr %5, align 8
  %31 = and i64 %30, 4611686018427387904
  %32 = icmp ne i64 %31, 0
  %33 = xor i1 %32, true
  br i1 %33, label %34, label %36

34:                                               ; preds = %29
  %35 = load i64, ptr %4, align 8
  br label %39

36:                                               ; preds = %29
  %37 = load i64, ptr %5, align 8
  %38 = shl i64 %37, 3
  br label %39

39:                                               ; preds = %34, %36
  %40 = phi i64 [ %38, %36 ], [ %35, %34 ]
  br label %41

41:                                               ; preds = %28, %39
  %42 = phi i64 [ %40, %39 ], [ 23, %28 ]
  %43 = mul i64 %42, 2
  %44 = call i64 @llvm.smax.i64(i64 %1, i64 %43)
  %45 = add i64 %44, 7
  %46 = ashr i64 %45, 3
  %47 = shl i64 %46, 3
  %48 = add i64 %47, 8
  %49 = call ptr @KGEN_CompilerRT_AlignedAlloc(i64 1, i64 %48)
  %50 = getelementptr { i64 }, ptr %49, i32 0, i32 0
  store i64 1, ptr %50, align 8
  %51 = getelementptr inbounds i8, ptr %49, i32 8
  %52 = sub i64 %16, 8
  %53 = getelementptr inbounds i8, ptr %24, i64 %52
  %54 = getelementptr inbounds i8, ptr %51, i64 %52
  %55 = icmp sge i64 %16, 8
  %56 = sub i64 %16, 4
  %57 = getelementptr inbounds i8, ptr %24, i64 %56
  %58 = getelementptr inbounds i8, ptr %51, i64 %56
  %59 = icmp eq i64 %16, 0
  %60 = getelementptr inbounds i8, ptr %24, i32 1
  %61 = getelementptr inbounds i8, ptr %49, i32 9
  %62 = sub i64 %16, 1
  %63 = getelementptr inbounds i8, ptr %24, i64 %62
  %64 = getelementptr inbounds i8, ptr %51, i64 %62
  %65 = sub i64 %16, 2
  %66 = getelementptr inbounds i8, ptr %24, i64 %65
  %67 = getelementptr inbounds i8, ptr %51, i64 %65
  %68 = icmp sle i64 %16, 2
  %69 = icmp sle i64 %16, 16
  %70 = icmp slt i64 %16, 5
  br i1 %70, label %71, label %82

71:                                               ; preds = %41
  br i1 %59, label %72, label %73

72:                                               ; preds = %71
  br label %81

73:                                               ; preds = %71
  %74 = load i8, ptr %24, align 1
  store i8 %74, ptr %51, align 1
  %75 = load i8, ptr %63, align 1
  store i8 %75, ptr %64, align 1
  br i1 %68, label %76, label %77

76:                                               ; preds = %73
  br label %80

77:                                               ; preds = %73
  %78 = load i8, ptr %60, align 1
  store i8 %78, ptr %61, align 1
  %79 = load i8, ptr %66, align 1
  store i8 %79, ptr %67, align 1
  br label %80

80:                                               ; preds = %76, %77
  br label %81

81:                                               ; preds = %72, %80
  br label %119

82:                                               ; preds = %41
  br i1 %69, label %83, label %91

83:                                               ; preds = %82
  br i1 %55, label %84, label %87

84:                                               ; preds = %83
  %85 = load i64, ptr %24, align 1
  store i64 %85, ptr %51, align 1
  %86 = load i64, ptr %53, align 1
  store i64 %86, ptr %54, align 1
  br label %90

87:                                               ; preds = %83
  %88 = load i32, ptr %24, align 1
  store i32 %88, ptr %51, align 1
  %89 = load i32, ptr %57, align 1
  store i32 %89, ptr %58, align 1
  br label %90

90:                                               ; preds = %84, %87
  br label %118

91:                                               ; preds = %82
  %92 = udiv i64 %16, 32
  %93 = mul i64 %92, 32
  br label %94

94:                                               ; preds = %99, %91
  %95 = phi i64 [ 0, %91 ], [ %100, %99 ]
  %96 = icmp slt i64 %95, %93
  br i1 %96, label %97, label %98

97:                                               ; preds = %94
  br label %99

98:                                               ; preds = %94
  br label %104

99:                                               ; preds = %97
  %100 = add i64 %95, 32
  %101 = getelementptr inbounds i8, ptr %24, i64 %95
  %102 = load <32 x i8>, ptr %101, align 1
  %103 = getelementptr inbounds i8, ptr %51, i64 %95
  store <32 x i8> %102, ptr %103, align 1
  br label %94

104:                                              ; preds = %98
  br label %105

105:                                              ; preds = %112, %104
  %106 = phi i64 [ %93, %104 ], [ %113, %112 ]
  %107 = sub i64 %16, %106
  %108 = call i64 @llvm.smax.i64(i64 %107, i64 0)
  %109 = icmp sgt i64 %108, 0
  br i1 %109, label %110, label %111

110:                                              ; preds = %105
  br label %112

111:                                              ; preds = %105
  br label %117

112:                                              ; preds = %110
  %113 = add i64 %106, 1
  %114 = getelementptr inbounds i8, ptr %24, i64 %106
  %115 = load i8, ptr %114, align 1
  %116 = getelementptr inbounds i8, ptr %51, i64 %106
  store i8 %115, ptr %116, align 1
  br label %105

117:                                              ; preds = %111
  br label %118

118:                                              ; preds = %90, %117
  br label %119

119:                                              ; preds = %81, %118
  %120 = load i64, ptr %5, align 8
  %121 = and i64 %120, 4611686018427387904
  %122 = icmp ne i64 %121, 0
  br i1 %122, label %123, label %132

123:                                              ; preds = %119
  %124 = load ptr, ptr %3, align 8
  %125 = getelementptr inbounds i8, ptr %124, i32 -8
  %126 = getelementptr { i64 }, ptr %125, i32 0, i32 0
  %127 = atomicrmw sub ptr %126, i64 1 release, align 8
  %128 = icmp eq i64 %127, 1
  br i1 %128, label %129, label %130

129:                                              ; preds = %123
  fence acquire
  call void @KGEN_CompilerRT_AlignedFree(ptr %125)
  br label %131

130:                                              ; preds = %123
  br label %131

131:                                              ; preds = %129, %130
  br label %133

132:                                              ; preds = %119
  br label %133

133:                                              ; preds = %131, %132
  store i64 %16, ptr %4, align 8
  store ptr %51, ptr %3, align 8
  store i64 %46, ptr %5, align 8
  %134 = or i64 %46, 4611686018427387904
  store i64 %134, ptr %5, align 8
  ret void
}

define internal { ptr, i64, i64 } @"std::collections::string::string::String::_add[::Bool,::Origin[$0],::Bool,::Origin[$2]](::Span[$0, ::SIMD[::DType(uint8), ::Int(1)], $1],::Span[$2, ::SIMD[::DType(uint8), ::Int(1)], $3])_REMOVED_ARG"({ ptr, i64 } noundef %0, { ptr, i64 } noundef %1) #0 {
  %3 = alloca { ptr, i64, i64 }, i64 1, align 8
  %4 = extractvalue { ptr, i64 } %0, 1
  %5 = extractvalue { ptr, i64 } %1, 1
  %6 = add i64 %4, %5
  %7 = add i64 %6, 7
  %8 = ashr i64 %7, 3
  call void @llvm.lifetime.end.p0(ptr %3)
  %9 = getelementptr { ptr, i64, i64 }, ptr %3, i32 0, i32 1
  %10 = getelementptr { ptr, i64, i64 }, ptr %3, i32 0, i32 0
  %11 = getelementptr { ptr, i64, i64 }, ptr %3, i32 0, i32 2
  call void @llvm.lifetime.start.p0(ptr %3)
  %12 = icmp sle i64 %6, 23
  br i1 %12, label %13, label %14

13:                                               ; preds = %2
  store i64 -9223372036854775808, ptr %11, align 8
  br label %22

14:                                               ; preds = %2
  store i64 %8, ptr %11, align 8
  %15 = shl i64 %8, 3
  %16 = add i64 %15, 8
  %17 = call ptr @KGEN_CompilerRT_AlignedAlloc(i64 1, i64 %16)
  %18 = getelementptr { i64 }, ptr %17, i32 0, i32 0
  store i64 1, ptr %18, align 8
  %19 = getelementptr inbounds i8, ptr %17, i32 8
  store ptr %19, ptr %10, align 8
  store i64 0, ptr %9, align 8
  %20 = load i64, ptr %11, align 8
  %21 = or i64 %20, 4611686018427387904
  store i64 %21, ptr %11, align 8
  br label %22

22:                                               ; preds = %13, %14
  %23 = shl i64 %6, 56
  %24 = load i64, ptr %11, align 8
  %25 = and i64 %24, -9223372036854775808
  %26 = icmp ne i64 %25, 0
  br i1 %26, label %27, label %31

27:                                               ; preds = %22
  %28 = load i64, ptr %11, align 8
  %29 = and i64 %28, -2233785415175766017
  %30 = or i64 %29, %23
  store i64 %30, ptr %11, align 8
  br label %32

31:                                               ; preds = %22
  store i64 %6, ptr %9, align 8
  br label %32

32:                                               ; preds = %27, %31
  %33 = call ptr @"std::collections::string::string::String::unsafe_ptr_mut(::String&,::Int$)"(ptr %3, i64 0)
  %34 = extractvalue { ptr, i64 } %0, 0
  %35 = sub i64 %4, 8
  %36 = getelementptr inbounds i8, ptr %34, i64 %35
  %37 = getelementptr inbounds i8, ptr %33, i64 %35
  %38 = icmp sge i64 %4, 8
  %39 = sub i64 %4, 4
  %40 = getelementptr inbounds i8, ptr %34, i64 %39
  %41 = getelementptr inbounds i8, ptr %33, i64 %39
  %42 = icmp eq i64 %4, 0
  %43 = getelementptr inbounds i8, ptr %34, i32 1
  %44 = getelementptr inbounds i8, ptr %33, i32 1
  %45 = sub i64 %4, 1
  %46 = getelementptr inbounds i8, ptr %34, i64 %45
  %47 = getelementptr inbounds i8, ptr %33, i64 %45
  %48 = sub i64 %4, 2
  %49 = getelementptr inbounds i8, ptr %34, i64 %48
  %50 = getelementptr inbounds i8, ptr %33, i64 %48
  %51 = icmp sle i64 %4, 2
  %52 = icmp sle i64 %4, 16
  %53 = icmp slt i64 %4, 5
  br i1 %53, label %54, label %65

54:                                               ; preds = %32
  br i1 %42, label %55, label %56

55:                                               ; preds = %54
  br label %64

56:                                               ; preds = %54
  %57 = load i8, ptr %34, align 1
  store i8 %57, ptr %33, align 1
  %58 = load i8, ptr %46, align 1
  store i8 %58, ptr %47, align 1
  br i1 %51, label %59, label %60

59:                                               ; preds = %56
  br label %63

60:                                               ; preds = %56
  %61 = load i8, ptr %43, align 1
  store i8 %61, ptr %44, align 1
  %62 = load i8, ptr %49, align 1
  store i8 %62, ptr %50, align 1
  br label %63

63:                                               ; preds = %59, %60
  br label %64

64:                                               ; preds = %55, %63
  br label %102

65:                                               ; preds = %32
  br i1 %52, label %66, label %74

66:                                               ; preds = %65
  br i1 %38, label %67, label %70

67:                                               ; preds = %66
  %68 = load i64, ptr %34, align 1
  store i64 %68, ptr %33, align 1
  %69 = load i64, ptr %36, align 1
  store i64 %69, ptr %37, align 1
  br label %73

70:                                               ; preds = %66
  %71 = load i32, ptr %34, align 1
  store i32 %71, ptr %33, align 1
  %72 = load i32, ptr %40, align 1
  store i32 %72, ptr %41, align 1
  br label %73

73:                                               ; preds = %67, %70
  br label %101

74:                                               ; preds = %65
  %75 = udiv i64 %4, 32
  %76 = mul i64 %75, 32
  br label %77

77:                                               ; preds = %82, %74
  %78 = phi i64 [ 0, %74 ], [ %83, %82 ]
  %79 = icmp slt i64 %78, %76
  br i1 %79, label %80, label %81

80:                                               ; preds = %77
  br label %82

81:                                               ; preds = %77
  br label %87

82:                                               ; preds = %80
  %83 = add i64 %78, 32
  %84 = getelementptr inbounds i8, ptr %34, i64 %78
  %85 = load <32 x i8>, ptr %84, align 1
  %86 = getelementptr inbounds i8, ptr %33, i64 %78
  store <32 x i8> %85, ptr %86, align 1
  br label %77

87:                                               ; preds = %81
  br label %88

88:                                               ; preds = %95, %87
  %89 = phi i64 [ %76, %87 ], [ %96, %95 ]
  %90 = sub i64 %4, %89
  %91 = call i64 @llvm.smax.i64(i64 %90, i64 0)
  %92 = icmp sgt i64 %91, 0
  br i1 %92, label %93, label %94

93:                                               ; preds = %88
  br label %95

94:                                               ; preds = %88
  br label %100

95:                                               ; preds = %93
  %96 = add i64 %89, 1
  %97 = getelementptr inbounds i8, ptr %34, i64 %89
  %98 = load i8, ptr %97, align 1
  %99 = getelementptr inbounds i8, ptr %33, i64 %89
  store i8 %98, ptr %99, align 1
  br label %88

100:                                              ; preds = %94
  br label %101

101:                                              ; preds = %73, %100
  br label %102

102:                                              ; preds = %64, %101
  %103 = getelementptr inbounds i8, ptr %33, i64 %4
  %104 = extractvalue { ptr, i64 } %1, 0
  %105 = sub i64 %5, 8
  %106 = getelementptr inbounds i8, ptr %104, i64 %105
  %107 = getelementptr inbounds i8, ptr %103, i64 %105
  %108 = icmp sge i64 %5, 8
  %109 = sub i64 %5, 4
  %110 = getelementptr inbounds i8, ptr %104, i64 %109
  %111 = getelementptr inbounds i8, ptr %103, i64 %109
  %112 = icmp eq i64 %5, 0
  %113 = getelementptr inbounds i8, ptr %104, i32 1
  %114 = getelementptr inbounds i8, ptr %103, i32 1
  %115 = sub i64 %5, 1
  %116 = getelementptr inbounds i8, ptr %104, i64 %115
  %117 = getelementptr inbounds i8, ptr %103, i64 %115
  %118 = sub i64 %5, 2
  %119 = getelementptr inbounds i8, ptr %104, i64 %118
  %120 = getelementptr inbounds i8, ptr %103, i64 %118
  %121 = icmp sle i64 %5, 2
  %122 = icmp sle i64 %5, 16
  %123 = icmp slt i64 %5, 5
  br i1 %123, label %124, label %135

124:                                              ; preds = %102
  br i1 %112, label %125, label %126

125:                                              ; preds = %124
  br label %134

126:                                              ; preds = %124
  %127 = load i8, ptr %104, align 1
  store i8 %127, ptr %103, align 1
  %128 = load i8, ptr %116, align 1
  store i8 %128, ptr %117, align 1
  br i1 %121, label %129, label %130

129:                                              ; preds = %126
  br label %133

130:                                              ; preds = %126
  %131 = load i8, ptr %113, align 1
  store i8 %131, ptr %114, align 1
  %132 = load i8, ptr %119, align 1
  store i8 %132, ptr %120, align 1
  br label %133

133:                                              ; preds = %129, %130
  br label %134

134:                                              ; preds = %125, %133
  br label %172

135:                                              ; preds = %102
  br i1 %122, label %136, label %144

136:                                              ; preds = %135
  br i1 %108, label %137, label %140

137:                                              ; preds = %136
  %138 = load i64, ptr %104, align 1
  store i64 %138, ptr %103, align 1
  %139 = load i64, ptr %106, align 1
  store i64 %139, ptr %107, align 1
  br label %143

140:                                              ; preds = %136
  %141 = load i32, ptr %104, align 1
  store i32 %141, ptr %103, align 1
  %142 = load i32, ptr %110, align 1
  store i32 %142, ptr %111, align 1
  br label %143

143:                                              ; preds = %137, %140
  br label %171

144:                                              ; preds = %135
  %145 = udiv i64 %5, 32
  %146 = mul i64 %145, 32
  br label %147

147:                                              ; preds = %152, %144
  %148 = phi i64 [ 0, %144 ], [ %153, %152 ]
  %149 = icmp slt i64 %148, %146
  br i1 %149, label %150, label %151

150:                                              ; preds = %147
  br label %152

151:                                              ; preds = %147
  br label %157

152:                                              ; preds = %150
  %153 = add i64 %148, 32
  %154 = getelementptr inbounds i8, ptr %104, i64 %148
  %155 = load <32 x i8>, ptr %154, align 1
  %156 = getelementptr inbounds i8, ptr %103, i64 %148
  store <32 x i8> %155, ptr %156, align 1
  br label %147

157:                                              ; preds = %151
  br label %158

158:                                              ; preds = %165, %157
  %159 = phi i64 [ %146, %157 ], [ %166, %165 ]
  %160 = sub i64 %5, %159
  %161 = call i64 @llvm.smax.i64(i64 %160, i64 0)
  %162 = icmp sgt i64 %161, 0
  br i1 %162, label %163, label %164

163:                                              ; preds = %158
  br label %165

164:                                              ; preds = %158
  br label %170

165:                                              ; preds = %163
  %166 = add i64 %159, 1
  %167 = getelementptr inbounds i8, ptr %104, i64 %159
  %168 = load i8, ptr %167, align 1
  %169 = getelementptr inbounds i8, ptr %103, i64 %159
  store i8 %168, ptr %169, align 1
  br label %158

170:                                              ; preds = %164
  br label %171

171:                                              ; preds = %143, %170
  br label %172

172:                                              ; preds = %134, %171
  %173 = load ptr, ptr %10, align 8
  %174 = load i64, ptr %9, align 8
  %175 = load i64, ptr %11, align 8
  call void @llvm.lifetime.end.p0(ptr %3)
  %176 = insertvalue { ptr, i64, i64 } undef, ptr %173, 0
  %177 = insertvalue { ptr, i64, i64 } %176, i64 %174, 1
  %178 = insertvalue { ptr, i64, i64 } %177, i64 %175, 2
  ret { ptr, i64, i64 } %178
}

; Function Attrs: allockind("free")
declare void @KGEN_CompilerRT_AlignedFree(ptr allocptr) #1

declare ptr @KGEN_CompilerRT_AsyncRT_CreateRuntime(i64) #0

declare void @KGEN_CompilerRT_AsyncRT_DestroyRuntime(ptr) #0

declare ptr @KGEN_CompilerRT_AsyncRT_GetCurrentRuntime() #0

declare ptr @KGEN_CompilerRT_GetOrCreateGlobal({ ptr, i64 }, ptr, ptr) #0

declare void @KGEN_CompilerRT_SetArgV(i32, ptr) #0

declare void @KGEN_CompilerRT_PrintStackTraceOnFault() #0

declare void @KGEN_CompilerRT_DestroyGlobals() #0

; Function Attrs: allockind("alloc,uninitialized,aligned") allocsize(1)
declare noalias ptr @KGEN_CompilerRT_AlignedAlloc(i64 allocalign, i64) #2

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(ptr captures(none)) #3

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(ptr captures(none)) #3

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.smax.i64(i64, i64) #4

attributes #0 = { "target-cpu"="skylake" "target-features"="+adx,+aes,+avx,+avx2,+bmi,+bmi2,+clflushopt,+cmov,+crc32,+cx16,+cx8,+f16c,+fma,+fsgsbase,+fxsr,+invpcid,+lzcnt,+mmx,+movbe,+pclmul,+popcnt,+prfchw,+rdrnd,+rdseed,+sahf,+sgx,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+ssse3,+x87,+xsave,+xsavec,+xsaveopt,+xsaves" }
attributes #1 = { allockind("free") "alloc-family"="kgen_aligned_allocator" "target-cpu"="skylake" "target-features"="+adx,+aes,+avx,+avx2,+bmi,+bmi2,+clflushopt,+cmov,+crc32,+cx16,+cx8,+f16c,+fma,+fsgsbase,+fxsr,+invpcid,+lzcnt,+mmx,+movbe,+pclmul,+popcnt,+prfchw,+rdrnd,+rdseed,+sahf,+sgx,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+ssse3,+x87,+xsave,+xsavec,+xsaveopt,+xsaves" }
attributes #2 = { allockind("alloc,uninitialized,aligned") allocsize(1) "alloc-family"="kgen_aligned_allocator" "target-cpu"="skylake" "target-features"="+adx,+aes,+avx,+avx2,+bmi,+bmi2,+clflushopt,+cmov,+crc32,+cx16,+cx8,+f16c,+fma,+fsgsbase,+fxsr,+invpcid,+lzcnt,+mmx,+movbe,+pclmul,+popcnt,+prfchw,+rdrnd,+rdseed,+sahf,+sgx,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+ssse3,+x87,+xsave,+xsavec,+xsaveopt,+xsaves" }
attributes #3 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #4 = { nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none) }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
