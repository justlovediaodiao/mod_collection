EXTERN RoadieOnProcessorExit:PROC
EXTERN RoadieOnOuterExit:PROC
EXTERN RoadieOnSetControlRotation:PROC

EXTERN g_processor_return:QWORD
EXTERN g_outer_return:QWORD
EXTERN g_set_rotation_return:QWORD
EXTERN g_movement_rotation_return:QWORD
EXTERN g_roadie_tuning_class_id:DWORD

PUBLIC RoadieProcessorDetour
PUBLIC RoadieOuterExitDetour
PUBLIC RoadieSetRotationDetour
PUBLIC RoadieMovementTypeDetour

.code

; Both mid-function sites enter with RSP aligned to 16 bytes. Preserve all
; volatile integer and vector state before crossing into C++.
RoadieProcessorDetour PROC
    mov r11, rsp
    pushfq
    push rax
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    sub rsp, 80h
    vmovdqu xmmword ptr [rsp+20h], xmm0
    vmovdqu xmmword ptr [rsp+30h], xmm1
    vmovdqu xmmword ptr [rsp+40h], xmm2
    vmovdqu xmmword ptr [rsp+50h], xmm3
    vmovdqu xmmword ptr [rsp+60h], xmm4
    vmovdqu xmmword ptr [rsp+70h], xmm5
    mov rcx, rbx
    mov rdx, r11
    vzeroupper
    call RoadieOnProcessorExit
    vmovdqu xmm0, xmmword ptr [rsp+20h]
    vmovdqu xmm1, xmmword ptr [rsp+30h]
    vmovdqu xmm2, xmmword ptr [rsp+40h]
    vmovdqu xmm3, xmmword ptr [rsp+50h]
    vmovdqu xmm4, xmmword ptr [rsp+60h]
    vmovdqu xmm5, xmmword ptr [rsp+70h]
    add rsp, 80h
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rax
    popfq
    vzeroupper
    lea r11, [rsp+120h]
    jmp qword ptr [g_processor_return]
RoadieProcessorDetour ENDP

RoadieOuterExitDetour PROC
    mov r11, rsp
    pushfq
    push rax
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    sub rsp, 80h
    vmovdqu xmmword ptr [rsp+20h], xmm0
    vmovdqu xmmword ptr [rsp+30h], xmm1
    vmovdqu xmmword ptr [rsp+40h], xmm2
    vmovdqu xmmword ptr [rsp+50h], xmm3
    vmovdqu xmmword ptr [rsp+60h], xmm4
    vmovdqu xmmword ptr [rsp+70h], xmm5
    mov rcx, rdi
    vzeroupper
    call RoadieOnOuterExit
    vmovdqu xmm0, xmmword ptr [rsp+20h]
    vmovdqu xmm1, xmmword ptr [rsp+30h]
    vmovdqu xmm2, xmmword ptr [rsp+40h]
    vmovdqu xmm3, xmmword ptr [rsp+50h]
    vmovdqu xmm4, xmmword ptr [rsp+60h]
    vmovdqu xmm5, xmmword ptr [rsp+70h]
    add rsp, 80h
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rax
    popfq
    vzeroupper
    lea r11, [rsp+1B8h]
    jmp qword ptr [g_outer_return]
RoadieOuterExitDetour ENDP

; SetControlRotation enters with RSP == 8 (mod 16). The extra eight bytes in
; this frame restore the required Windows x64 call alignment.
RoadieSetRotationDetour PROC
    mov r11, rsp
    pushfq
    push rax
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    sub rsp, 88h
    vmovdqu xmmword ptr [rsp+20h], xmm0
    vmovdqu xmmword ptr [rsp+30h], xmm1
    vmovdqu xmmword ptr [rsp+40h], xmm2
    vmovdqu xmmword ptr [rsp+50h], xmm3
    vmovdqu xmmword ptr [rsp+60h], xmm4
    vmovdqu xmmword ptr [rsp+70h], xmm5
    mov r8, qword ptr [r11]
    vzeroupper
    call RoadieOnSetControlRotation
    vmovdqu xmm0, xmmword ptr [rsp+20h]
    vmovdqu xmm1, xmmword ptr [rsp+30h]
    vmovdqu xmm2, xmmword ptr [rsp+40h]
    vmovdqu xmm3, xmmword ptr [rsp+50h]
    vmovdqu xmm4, xmmword ptr [rsp+60h]
    vmovdqu xmm5, xmmword ptr [rsp+70h]
    add rsp, 88h
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rax
    popfq
    mov rax, rsp
    mov qword ptr [rax+08h], rbx
    jmp qword ptr [g_set_rotation_return]
RoadieSetRotationDetour ENDP

; RDI is raw tuning data, not a UObject. The sole caller of this helper
; holds the movement context in RBX; its saved RBX is at RSP+30h here.
; Context+28h is the FInstancedStruct UScriptStruct pointer; context+30h
; is its raw data pointer. Check the descriptor's FName, not the raw data.
RoadieMovementTypeDetour PROC
    mov dl, al
    cmp al, 1
    jne movement_done
    mov r11, qword ptr [rsp+30h]
    mov r11, qword ptr [r11+28h]
    test r11, r11
    je movement_done
    mov r11d, dword ptr [r11+18h]
    cmp r11d, dword ptr [g_roadie_tuning_class_id]
    jne movement_done
    mov dl, 2
movement_done:
    mov rcx, rbx
    jmp qword ptr [g_movement_rotation_return]
RoadieMovementTypeDetour ENDP

END
