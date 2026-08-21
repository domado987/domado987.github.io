---
title: "[3편] 어셈블리 명령어와 제어 흐름, 메모리 스택 구조"
date: 2026-08-20 8:00:00 +0900
categories: [CS, Assembly]
tags: [mov, cmp-jmp, stack, control-flow]
published: true
---

```nasm
section .text
    global _start

_start:
    mov rdi, 5
    mov rsi, 3
    call add_func

    mov rax, 60
    xor rdi, rdi
    syscall

add_func:
    push rbp
    mov rbp, rsp

    mov rax, rdi
    add rax, rsi

    mov rsp, rbp
    pop rbp
    ret
```
위 코드는 3과 5를 더한 후, exit(0)을 호출하는 아주 간단한 코드다.<br>
C언어로 코드를 짜면 훨씬 간단할텐데, 심지어 파이썬으로는 1줄로도 가능하다.<br>
그러나, 어셈블리 코드에서는 함수를 호출하고 값이 레지스터에서 변경되고, syscall을 직접 호출하는 과정을 한 줄 한 줄 따라가며 확인할 수 있다.<br>
포너블에서는 이런 한 스텝 한 스텝을 관찰하며 취약점을 찾고, 그걸 이용해 공격 / 방어를 하는 것이 목표다.<br>
어떻게 보면 아주 변태적이라고 할 수 있는 과정이지만,,, 나름 재미가 있는 것 같다...<br>
<br>
이번 블로그에서는 기본적인 어셈블리 명령어와 제어 흐름, 스택 메모리 구조에 대해서 설명한다.<br>
추가로 설명할 어셈블리 명령어들은 Intel 문법에 맞춰서 작성되었다.<br>

## 데이터 이동 명령어 & 스택 프레임
### MOV, LEA
`MOV dst, src` — 값 복사 (레지스터 ↔ 레지스터, 레지스터 ↔ 메모리, 즉시값→레지스터)<br>
이름이 **MOV**라서 값의 이동(move)이라고 생각할 수 있다. 실제로 어원은 move가 맞지만, 이 함수는 **복사**를 실행하는 명령어다.

`LEA dst, [src]` — 메모리를 읽지 않고 주소 계산 결과만 저장 (lea rax, [rbx+rcx*4+8])<br>
**MOV**와 동일한 결과를 내지만, 성능 차원에서는 다른 결과를 낸다.<br>
**MOV**를 이용해서 값을 복사해오려면 add와 mul의 연산 과정을 여러번 거져야 하지만, **LEA**를 이용하면 한 클럭에 해결할 수 있다.<br>
한 번에 3-operand 연산이 가능하기 때문에 심지어는 단순 연산을 할 때도 **LEA** 를 이용하는 경우도 있다.<br>

```c
int arr[5];
int x = arr[2];
```

```nasm
lea    rax, [rbp-0x20]      ; arr의 시작 주소 계산 (읽기 아님!)
mov    eax, [rax+0x8]       ; arr[2] 값을 실제로 읽음 (2*4=8 offset)
mov    [rbp-0x4], eax       ; x = arr[2]
```

→ LEA는 주소만 계산하고, MOV는 실제 메모리 접근한다.<br>
값인지 주소인지 MOV/LEA로 구분하는 게 디스어셈블리 독해의 기본기라고 할 수 있다.<br>

### PUSH, POP
```PUSH src``` — RSP -= 8 후 src를 [RSP]에 저장<br>
```POP dst``` — [RSP]에서 dst를 읽고 RSP += 8<br>
rsp(Register Stack Pointer)는 x86-64 CPU에서 현재 메모리 스택(Stack)의 맨 위(Top) 주소를 가리키는 전용 레지스터다.<br>
rsp의 정확한 이해를 위해서는 스택 프레임에 대해서 알고 있어야 한다.

### 스택 프레임 (Stack Frame)
함수가 호출될 때마다 스택 위에 생기는 "그 함수만의 작업 공간"이다.<br>
지역변수, 저장된 레지스터, 리턴 주소가 스택 프레임 구조 위에 쌓이게 된다.<br>

1) 왜 필요한가?<br>
프로그램을 실행하며 여러 함수가 호출된다. 그럴 때마다 독립된 지역변수 공간과 **돌아갈 위치** 가 필요한데, 이걸 관리하는 것이 스택 프레임이다.<br>
함수 호출할 때마다 새로 쌓이고(push), 함수가 끝나면 통째로 사라진다(pop).<br><br>

2) 메모리 레이아웃 (낮은 주소 -> 높은 주소)<br>
x86-64에서 스택은 높은 주소에서 낮은 주소 방향으로 자란다는 게 핵심이다.

| 주소 방향 | 구성 요소 | 설명 |
|:---:|---|---|
| 높음 ↑ | 함수 인자 (7번째~) | 스택으로 전달되는 인자 (1~6번째는 레지스터) |
|  | Return Address | call이 push한, 함수 끝나고 돌아갈 주소 |
|  | Saved RBP | 이전 프레임의 RBP 값 (복구용) |
|  | Stack Canary | 있는 경우, BOF 탐지용 |
| 낮음 ↓ | 지역 변수 (buf, int i 등) | buf가 여기 위치, RSP가 가리키는 지점 근처 |

참고로 **버퍼 오버플로우(BOF)**의 핵심은 여기에 있다. <br>
버퍼는 낮은 주소에 있고, 리턴 주소는 높은 주소에 있다. 버퍼가 정해진 크기보다 큰 입력을 받게 되면, 리턴 주소를 덮어씌울 수 있고, 이를 이용해서 컴퓨터를 장악할 수 있게 된다.

3) RBP vs RSP<br>
RSP (Stack Pointer): 항상 스택의 "맨 꼭대기"를 가리킨다. push/pop 할 때마다 움직인다.<br>
RBP (Base Pointer): 현재 함수 프레임의 **"고정 기준점"**이 된다. 함수 실행 중엔 움직이지 않는다. (프레임 내 지역변수를 [rbp-0x4]처럼 상대주소로 접근하기 위한 기준)<br>

4) 함수 호출 스텝별 추적<br>
맨 위 코드를 기준으로 레지스터와 스택에 저장된 값들을 추적해보자<br>
**Step 1.** `mov rdi, 5` / `mov rsi, 3` → 인자를 레지스터로 전달 (RDI=5, RSI=3, x86-64 calling convention, 5편 참고)

**Step 2.** `call add_func` → 리턴 주소(`mov rax,60`의 위치)를 스택에 push, RIP를 add_func로 이동 (RSP -= 8)

**Step 3.** `push rbp` → _start의 RBP를 저장 (RSP -= 8)

**Step 4.** `mov rbp, rsp` → 현재 RSP 위치를 add_func의 기준점으로 고정

**Step 5.** `mov rax, rdi` / `add rax, rsi` → RAX = 5 + 3 = 8 (리턴값은 관례상 RAX)

**Step 6.** `mov rsp, rbp` → RSP를 RBP 위치로 복귀 (지역변수 없어서 실질 변화 없음)

**Step 7.** `pop rbp` → _start의 원래 RBP 복구 (RSP += 8)

**Step 8.** `ret` → 스택 top(Return Address)을 RIP로 pop, RSP += 8

이 과정을 거치며 RAX = 8이 계산되고, RBP·RSP는 원래 상태로 복귀한다. x86-64에서 모든 함수 호출/복귀는 이 push-set-pop 패턴을 거친다.

**최종 스택 변화 (Step 2~4 누적)**<br>
RSP,RBP → [ Saved RBP ] ← Step 3~4<br>
[ Return Address ] ← Step 2<br>
[ 원래 있던 데이터 ]<br>
Step 6~8에서 이 순서 그대로 역순 반납됨 (RBP 복구 → RSP 복귀).<br>

## 산술 연산 명령어

### 기본 사칙연산
`ADD dst, src` — 덧셈<br>
`SUB dst, src` — 뺄셈<br>
`INC dst / DEC dst` — 1 증가/감소 (플래그 세팅이 ADD/SUB와 미묘하게 다름: CF는 영향 안 받음)<br>
### 곱셈/나눗셈
`MUL src` — 부호 없는 곱셈 (RAX * src → RDX:RAX)<br>
`IMUL src` — 부호 있는 곱셈 (1피연산자/2피연산자/3피연산자 형태 모두 존재)<br>
`DIV src` — 부호 없는 나눗셈 (RDX:RAX / src → RAX 몫, RDX 나머지)<br>
`IDIV src` — 부호 있는 나눗셈<br>

## 논리 및 비트연산 명령어

### 논리 연산
`AND dst, src` — 비트 AND (마스킹에 사용)<br>
`OR dst, src` — 비트 OR<br>
`XOR dst, src` — 비트 XOR (xor eax, eax는 mov eax, 0보다 짧아서 레지스터 초기화에 관용적으로 사용됨)<br>
`NOT dst` — 비트 반전 (1의 보수)<br>
### 시프트/로테이트
`SHL/SAL dst, count` — 왼쪽 시프트 (곱셈 최적화, x << 1 = x * 2)<br>
`SHR dst, count` — 오른쪽 논리 시프트 (부호 없는 나눗셈 최적화)<br>

## 비교 및 조건 분기 명령어
<!--CMP, TEST, JE/JNE, JG/JL(부호), JA/JB(무부호), JMP, CALL, RET-->
### 비교 명령어
`CMP a, b` — 내부적으로 SUB a, b 수행하되 결과는 버리고 플래그만 세팅<br>
**세팅되는 4가지 플래그**<br>

| 플래그 | 세팅 조건 | 의미 |
|---|---|---|
| **ZF** (Zero) | `a - b == 0` | a와 b가 같음 |
| **SF** (Sign) | 결과의 최상위 비트가 1 | 연산 결과가 음수로 해석됨 |
| **CF** (Carry) | `a < b` (unsigned 기준) | 뺄셈에서 빌림(borrow) 발생 |
| **OF** (Overflow) | 부호 있는 연산에서 오버플로우 발생 | 결과가 부호 있는 범위를 벗어남 |

`TEST dst, src` — 내부적으로 AND 수행 후 결과는 버리고 플래그만 세팅<br>
`TEST eax, eax`가 `CMP eax, 0`보다 선호되는 이유(연산 바이트 수 절약) — 디스어셈블리에서 매우 흔한 패턴<br>
### 무조건 분기
`JMP target` — 무조건 점프<br>
`JMP rax / JMP [rax]` — 간접 점프<br>
`CALL target` — 점프 + 리턴 주소를 스택에 push (RET과 짝을 이루는 핵심 명령어)<br>
`RET` — 사실상 POP RIP (스택 최상단 값을 RIP로 복사)<br>
### 조건부 분기
**부호 있는 비교**<br>
`JG`/`JNLE` (greater, ZF=0 AND SF=OF)<br>
`JGE`/`JNL` (greater or equal, SF=OF)<br>
`JL`/`JNGE` (less, SF≠OF)<br>
`JLE`/`JNG` (less or equal, ZF=1 OR SF≠OF)<br>
**부호 없는 비교**<br>
`JA`/`JNBE` (above, CF=0 AND ZF=0)<br>
`JAE`/`JNB` (above or equal, CF=0)<br>
`JB`/`JNAE` (below, CF=1)<br>
`JBE`/`JNA` (below or equal, CF=1 OR ZF=1)<br>
**단일 플래그**<br>
`JE`/`JZ` (ZF=1), `JNE`/`JNZ` (ZF=0)<br>
## 실전 코드 매칭
### 1. MOV / LEA — 변수 접근과 배열 인덱싱
```c
int arr[5];
int x = arr[2];
```
```nasm
lea    rax, [rbp-0x20]      ; arr의 시작 주소 계산 (읽기 아님!)
mov    eax, [rax+0x8]       ; arr[2] 값을 실제로 읽음 (2*4=8 offset)
mov    [rbp-0x4], eax       ; x = arr[2]
```
→ LEA는 주소만 계산, MOV는 실제 메모리 접근.
### 2. SUB (스택 프레임) + XOR (레지스터 초기화)
```c
void func() {
    int buf[10];
    int i = 0;
}
```
```nasm
push   rbp
mov    rbp, rsp
sub    rsp, 0x30            ; buf[10] + i를 위한 지역변수 공간 확보
xor    eax, eax             ; i = 0 (mov eax,0 보다 1바이트 짧아서 컴파일러가 선호)
mov    [rbp-0x4], eax
```
→ sub rsp, N이 스택 프레임 크기 = 실제 버퍼 오버플로우 시 canary/saved rbp/ret addr까지 거리 계산의 기준점.
### 3. CMP / TEST + 조건 분기 — if문 실체
```c
if (x == 0) { foo(); }
if (a > b) { bar(); }        // 부호 있는 비교
if ((unsigned)a > (unsigned)b) { baz(); }  // 부호 없는 비교
```
```nasm
; if (x == 0)
mov    eax, [rbp-0x4]
test   eax, eax              ; eax & eax, 결과 0이면 ZF=1
jne    skip_foo              ; 0이 아니면 건너뜀
call   foo

; if (a > b) — 부호 있음
mov    eax, [rbp-0x8]
cmp    eax, [rbp-0xc]
jle    skip_bar              ; a <= b면 건너뜀 (JG의 반대)
call   bar

; unsigned 비교였다면 jle 대신 jbe가 나왔을 것
```
→ TEST eax,eax는 if(x==0)이나 if(x) 패턴의 시그니처. JG/JLE 계열이면 부호 있는 비교, JA/JBE 계열이면 부호 없는 비교
### 4. IMUL / CDQ+IDIV — 곱셈·나눗셈 실체
```c
int result = (a * 3) / b;
```
```nasm
mov    eax, [rbp-0x4]       ; a
imul   eax, eax, 0x3        ; a * 3
cdq                         ; eax를 edx:eax로 부호 확장 (idiv 전 필수)
idiv   dword ptr [rbp-0x8]  ; edx:eax / b → 몫은 eax, 나머지는 edx
mov    [rbp-0xc], eax       ; result
```
→ cdq가 보이면 무조건 바로 뒤에 idiv가 따라옴 — 이 패턴을 통으로 외워두면 디스어셈블리 읽는 속도가 확 빨라짐.
### 5. SHL / SHR — 비트 시프트 최적화 코드
```c
int x = n * 4;   // 컴파일러가 SHL로 최적화하는 경우가 많음
int y = m / 2;   // 부호 없는 경우 SHR로 최적화
```
```nasm
mov    eax, [rbp-0x4]
shl    eax, 0x2              ; n << 2 = n * 4
mov    [rbp-0x8], eax

mov    eax, [rbp-0xc]
shr    eax, 0x1              ; m >> 1 = m / 2 (unsigned일 때만)
mov    [rbp-0x10], eax
```
→ 곱셈/나눗셈 코드인데 IMUL/IDIV 대신 SHL/SHR만 보인다면 컴파일러 최적화 흔적 — 소스 복원할 때 헷갈리지 않게 알아둬야 함.
