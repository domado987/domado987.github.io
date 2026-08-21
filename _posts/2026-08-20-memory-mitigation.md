---
title: "메모리 보호 기법(Mitigation)"
date: 2026-08-20 22:00:00 +0900
categories: [Security, Pwnable]
tags: [pwnable, binary-exploitation, nx, aslr, pie, stack-canary, relro, rop, mitigation]
published: false
---
보통 시스템 해킹 문제를 풀 때, 리눅스 실행 파일(ELF)에 적용된 보호 기법을 가장 먼저 확인한다.<br>
checksec 명령어를 통해서 어떤 보호 기법이 적용되어 있는지를 확인하는데, 5개의 핵심적인 체크 항목이 있다.<br>

```
stack canary
nx
aslr
pie
relro
```
이 다섯개가 어떤 역할을 하고, 어떻게 파훼할 수 있는지 알아보자<br>

### 1. NX (No-eXecute) / DEP

**존재 이유**

초기 익스플로잇은 스택이나 힙에 셸코드를 직접 주입하고 그 주소로 리턴/점프해서 바로 실행시키는 방식이었습니다. 메모리 영역이 "쓰기 가능 = 실행 가능"이었기 때문에 가능했던 공격이고, 이를 막기 위해 CPU에 하드웨어 비트(x86의 경우 NX bit, ARM은 XN bit)가 추가되면서 OS가 페이지 단위로 실행 권한을 제어할 수 있게 됐습니다.

**보안 효과**

스택/힙 등 데이터 영역에 올린 셸코드는 실행 권한이 없어서 점프해도 SIGSEGV로 죽습니다. "쓰기 가능한 메모리에 코드를 심고 실행"하는 가장 직관적인 공격 경로를 원천 차단합니다.

**파훼 방법**

코드를 새로 심는 대신 이미 실행 권한이 있는 기존 코드(바이너리 자체 또는 libc)를 재사용합니다.

- **ret2libc**: libc 내 함수(system 등)로 바로 리턴
- **ROP (Return-Oriented Programming)**: 여러 gadget(ret으로 끝나는 짧은 명령어 조각)을 체이닝해서 임의 로직 구성
- **ret2syscall / SROP**: 시스템콜을 직접 조립해서 실행 (강훈님이 최근 하신 SROP 두 단계 스택 피벗이 여기 해당)
- mmap으로 RWX 메모리를 새로 할당받아 거기에 셸코드를 올리는 방식(강훈님이 하신 shellcode+mmap 챌린지)도 우회 범주에 들어갑니다 — NX 자체를 뚫는 게 아니라 "실행 가능한 새 메모리"를 합법적으로 확보하는 방식이라는 점이 포인트.

---

### 2. ASLR (Address Space Layout Randomization)

**존재 이유**

NX가 생기면서 공격자들이 ret2libc/ROP로 옮겨갔는데, 이 기법들은 정확한 함수/gadget 주소를 알아야 동작합니다. 바이너리와 라이브러리 로드 주소가 매번 고정이면 한 번 분석해서 얻은 주소를 계속 재사용할 수 있었고, 이를 막기 위해 커널이 프로세스 실행마다 스택·힙·mmap·라이브러리 베이스를 랜덤 배치하도록 만든 게 ASLR입니다.

**보안 효과**

공격자가 사전에 주소를 하드코딩해서 짜둔 exploit이 무력화됩니다. 정확한 주소를 모르면 ROP 체인도, ret2libc도 구성할 수 없습니다.

**파훼 방법**

"주소 하나를 leak해서 나머지를 오프셋으로 계산"하는 게 핵심 대응입니다.

- 포맷 스트링 버그로 스택/GOT 상의 포인터 값 직접 출력
- 함수 호출 결과(예: puts로 GOT 엔트리 출력)로 libc base 역산
- Partial RELRO 환경에서 GOT leak → libc base 계산
- 브루트포스(단, 리눅스는 보통 하위 12비트 정도만 랜덤화되지 않아 완전 무작위는 아니라서 이론상 가능하지만 비실용적)

리눅스 ASLR은 항목별로 독립적으로 적용된다는 점도 기억해두면 좋습니다 — 스택, 힙, mmap(라이브러리 포함) 각각 따로 랜덤화되고, PIE가 꺼져있으면 바이너리 코드 자체는 랜덤화 대상에서 빠집니다.

---

### 3. PIE (Position Independent Executable)

**존재 이유**

ASLR이 라이브러리와 스택/힙은 랜덤화해도, 바이너리 본체가 항상 같은 고정 주소(예: `0x400000`)에 로드되면 그 안의 함수·gadget·GOT 주소는 여전히 하드코딩 가능했습니다. 공유 라이브러리처럼 실행 파일 자체도 상대주소 기반으로 컴파일해서 로드 시점에 임의 베이스로 올릴 수 있게 만든 게 PIE입니다.

**보안 효과**

바이너리 내부의 모든 심볼(함수, 전역 변수, GOT/PLT 등) 주소가 실행마다 랜덤화된 베이스에 따라 바뀝니다. `ROPgadget`으로 미리 뽑아둔 가젯 주소도 실제 실행 시엔 오프셋으로만 쓸모가 있고, 베이스를 모르면 무용지물입니다.

**파훼 방법**

바이너리 내부 주소 하나를 leak해서 베이스를 역산합니다.

- 스택에 남아있는 리턴 주소(코드 세그먼트 내 주소)를 leak → 저장된 오프셋을 빼서 base 계산
- 포맷 스트링으로 `$rip` 근처 스택 값 직접 읽기
- GOT 엔트리 leak (RELRO 상태에 따라 난이도 다름)

강훈님이 `fsb_overwrite`에서 겪으신 문제가 정확히 이 지점이에요 — 로컬에서 구한 "leak한 주소 - base"의 오프셋이 리모트 서버의 스택 레이아웃(환경변수, argv 차이 등으로 인한)이 달라서 그대로 안 먹히는 상황. PIE 자체보다는 leak 지점의 스택 프레임 구조가 로컬/리모트에서 다르게 정렬되는 게 진짜 원인인 경우가 많습니다.

---

### 4. Stack Canary (Stack Protector)

**존재 이유**

스택 버퍼 오버플로우로 지역 변수 버퍼 뒤에 있는 리턴 주소를 덮어써서 제어 흐름을 탈취하는 게 가장 고전적인 공격입니다. 이를 컴파일러 단에서 막기 위해, 함수 진입 시 버퍼와 리턴 주소 사이에 랜덤 값을 심어두고 함수 종료 직전에 그 값이 그대로인지 검사하도록 만든 게 canary입니다.

**보안 효과**

버퍼를 순차적으로 오버플로우시켜 리턴 주소까지 덮으려면 반드시 canary 값을 먼저 지나가야 하는데, 정확한 값을 모르고 덮으면 함수 리턴 시 `__stack_chk_fail`이 호출되어 프로세스가 즉시 강제 종료됩니다. 즉 "canary를 모르는 순차적 오버플로우"를 원천 차단합니다.

**파훼 방법**

- **Leak**: 포맷 스트링 버그나 정보 노출 취약점으로 canary 값을 직접 읽어냄
- **Byte-by-byte brute force**: fork 서버 환경에서 canary의 마지막 null byte를 이용해 한 바이트씩 맞춰가며 crash 여부로 값을 추론 (강훈님이 해보신 패턴)
- **비순차적 덮어쓰기**: 배열 인덱스 조작 등으로 canary를 건너뛰고 리턴 주소만 직접 덮는 경우 (canary 자체를 우회, leak 불필요)
- canary는 스레드마다 TLS(Thread Local Storage)에 저장되므로, 멀티스레드 환경에서 TLS 자체를 조작하는 고급 기법도 존재

---

### 5. RELRO (RELocation Read-Only)

**존재 이유**

동적 링킹 바이너리는 함수 호출 시 GOT(Global Offset Table)를 거쳐서 실제 라이브러리 함수 주소로 점프합니다. lazy binding 방식에서는 GOT가 처음엔 PLT stub을 가리키다가 최초 호출 시점에 실제 주소로 채워지는데, 이 GOT 영역이 쓰기 가능한 상태로 남아있다 보니 공격자가 임의 쓰기(arbitrary write) 취약점으로 GOT 엔트리를 조작해 제어 흐름을 탈취하는 경로가 생겼습니다. 이를 막기 위해 GOT를 read-only로 만드는 보호가 도입됐습니다.

**보안 효과**

- **Partial RELRO**: `.got` 등 일부 세그먼트만 read-only, `.got.plt`는 여전히 쓰기 가능 → GOT overwrite 공격이 여전히 가능
- **Full RELRO**: 프로그램 시작 시 모든 심볼을 즉시 바인딩(eager binding)하고 링킹이 끝난 뒤 GOT 전체를 read-only로 mprotect → GOT overwrite가 완전히 막힘

**파훼 방법**

Full RELRO 환경에서는 GOT를 못 건드리니 다른 쓰기 가능한 함수 포인터를 노립니다.

- `__free_hook`, `__malloc_hook` 등 힙 후킹 포인터 덮어쓰기 (단, 최신 glibc 2.34+에서는 hook 자체가 제거됨)
- `_IO_FILE` 구조체의 vtable 포인터 조작 (FSOP, House of Orange 계열)
- `_rtld_global`의 `dl_load_write_ptr` 등 링커 내부 구조체 조작해서 리졸버 흐름 자체를 하이재킹
- Partial RELRO라면 그냥 GOT overwrite로 충분

강훈님 Dreamhack 커리큘럼에 넣어두신 `_IO_FILE`, `_rtld_global` 파트가 정확히 "Full RELRO 걸린 최신 glibc 환경에서 GOT 대신 뭘 노리는가"에 대한 답입니다. hook 함수가 사라진 최신 libc(2.34+)에서 왜 이 구조체들을 공부해야 하는지 감이 잡히실 거예요.

# 바이너리 보호 기법: 적용 전/후 예시 비교

모든 주소와 값은 설명을 위한 가상의 예시입니다.

---

## 1. NX (No-eXecute)

### 예시 코드

c

```c
void vuln() {
    char buf[64];
    read(0, buf, 256);  // 버퍼 오버플로우 발생
}
```

### NX OFF (적용 전)

```
스택 레이아웃 (vuln 함수 실행 중):
0x7ffee000  [ buf[64]           ]
0x7ffee040  [ saved rbp          ]
0x7ffee048  [ return address     ]  <- 여기를 shellcode 주소로 덮음

공격 payload:
[ shellcode (execve /bin/sh) ] + [ padding ] + [ 0x7ffee000 ]
                                                  ^ buf 시작 주소로 리턴

결과: buf에 심어둔 shellcode가 실행됨 -> /bin/sh 획득
```

buf 자체가 실행 가능한 메모리이므로, 리턴 주소를 `buf`의 시작 주소(`0x7ffee000`)로 덮기만 하면 그 안에 넣어둔 셸코드가 그대로 실행됩니다.

### NX ON (적용 후)

```
동일한 payload로 0x7ffee000(buf)에 리턴 시도
-> buf가 있는 스택 페이지는 실행 권한(X)이 없음
-> SIGSEGV 발생, 프로세스 즉시 종료 (Segmentation fault)
```

### 우회: ROP로 재구성

```
공격 payload (예시 gadget 주소는 바이너리에서 실제 추출한 값이라 가정):
[ padding(72B) ]
+ pop rdi; ret;         (0x401234)
+ "/bin/sh\0" 문자열 주소 (0x402008)
+ system@plt 주소        (0x401050)

결과: buf가 아니라 이미 실행 권한이 있는 코드 영역(.text)의
      gadget들만 재사용 -> system("/bin/sh") 호출 성공
```

새 코드를 심는 게 아니라 이미 실행 가능한 기존 코드 조각만 짜깁기했기 때문에 NX 검사를 아예 거치지 않습니다.

---

## 2. ASLR

### ASLR OFF (적용 전)

```
$ ./vuln
libc base: 0x7ffff7dc0000   (항상 동일)
system():  0x7ffff7e10000   (항상 동일)

$ ./vuln   (다시 실행해도)
libc base: 0x7ffff7dc0000   (변화 없음)
```

공격자가 한 번 분석해서 얻은 `system()` 주소(`0x7ffff7e10000`)를 exploit 스크립트에 하드코딩하면 재실행해도 항상 그대로 통합니다.

python

```python
# ASLR OFF 환경의 exploit (하드코딩 가능)
payload = b'A'*72 + p64(0x7ffff7e10000)  # system() 고정 주소
```

### ASLR ON (적용 후)

```
$ ./vuln
libc base: 0x7f3a2c800000   (실행마다 랜덤)

$ ./vuln   (다시 실행하면)
libc base: 0x7f3a91200000   (또 바뀜)
```

같은 payload를 그대로 쓰면 `system()`이 실제로는 다른 주소에 있어서 엉뚱한 곳으로 점프 -> crash.

### 우회: leak 후 오프셋 계산

python

```python
# 1) 취약점으로 GOT에 걸린 puts()의 실제 주소를 leak
leaked_puts = 0x7f3a2c823020   # 프로그램 실행 후 매번 leak해서 얻음

# 2) libc 내부에서 puts와 base 사이의 오프셋은 항상 고정 (예: 0x823020)
libc_base = leaked_puts - 0x823020   # 0x7f3a2c800000

# 3) system, "/bin/sh" 오프셋도 고정값이므로 base에 더해서 계산
system_addr = libc_base + 0x050740
binsh_addr  = libc_base + 0x1d8698
```

랜덤화된 것은 "베이스 주소"뿐이고, 함수 간 상대적 거리(오프셋)는 항상 고정이라는 점을 이용합니다.

---

## 3. PIE

### 예시 코드

c

```c
void win() { system("/bin/sh"); }   // 원하는 함수
void main() { vuln(); }             // 취약 함수
```

### PIE OFF (적용 전)

```
$ objdump -d vuln
0000000000401196 <win>:   <- 항상 이 주소로 고정 (실행마다 동일)

exploit:
payload = b'A'*72 + p64(0x401196)   # win() 주소 하드코딩
```

바이너리가 `0x400000`대의 고정 베이스에 로드되므로, `win()` 같은 내부 함수 주소를 그냥 하드코딩해서 리턴 주소를 덮으면 끝납니다. leak이 전혀 필요 없습니다.

### PIE ON (적용 후)

```
$ ./vuln
win() 실제 주소: 0x55a2b3401196   (베이스가 실행마다 랜덤)

$ ./vuln   (다시 실행)
win() 실제 주소: 0x561f9c601196   (또 바뀜)
```

`0x401196`을 그대로 쓰면 실제 base가 다르므로 엉뚱한 주소로 점프.

### 우회: 코드 영역 주소 leak → 베이스 역산

python

```python
# 1) 스택에 남은 리턴 주소(main+15, 코드 영역 내 주소)를 포맷 스트링 등으로 leak
leaked = 0x55a2b34011a5   # main() 함수 내부 어떤 지점의 실제 주소

# 2) 그 지점이 바이너리 내에서 base로부터 몇 바이트 떨어져 있는지는
#    objdump로 미리 알 수 있음 (예: base + 0x11a5)
pie_base = leaked - 0x11a5          # 0x55a2b3400000

# 3) win()의 오프셋(0x1196)을 base에 더해서 실제 주소 계산
win_addr = pie_base + 0x1196        # 0x55a2b3401196
```

강훈님이 `fsb_overwrite`에서 겪으신 로컬/리모트 오프셋 불일치가 보통 이 단계 — leak하는 스택 위치나 오프셋 계산 기준이 환경마다 미묘하게 다른 경우에 발생합니다.

---

## 4. Stack Canary

### 예시 코드

c

```c
void vuln() {
    char buf[64];
    gets(buf);   // 경계 검사 없는 입력
}
```

### Canary 없음 (적용 전)

```
스택 레이아웃:
buf[64]  ->  saved rbp  ->  return address

payload = b'A' * 72 + p64(win_addr)
# buf(64) + rbp(8) = 72바이트 채운 뒤 바로 리턴 주소 덮어쓰기
# 별도 검사 없이 그대로 win()으로 점프 성공
```

### Canary 있음 (적용 후)

```
스택 레이아웃:
buf[64]  ->  canary(8B, 예: 0x00a1b2c3d4e5f600)  ->  saved rbp  ->  return address

payload = b'A' * 72 + p64(win_addr)
# 72바이트를 채우는 도중 canary 위치(offset 64~71)까지 덮어버림

함수 종료 시점 검사:
if (stack_canary != original_canary):
    __stack_chk_fail()   # "*** stack smashing detected ***"
    -> abort(), 리턴 주소까지 도달하지 못하고 강제 종료
```

canary 값을 모른 채 순차적으로 덮으면 리턴 주소에 도달하기 전에 이미 값이 깨져서 검사 단계에서 걸립니다.

### 우회 1: leak

python

```python
# 포맷 스트링으로 canary 값을 먼저 읽어냄
canary = leaked_value   # 0x00a1b2c3d4e5f600

payload = b'A'*64 + p64(canary) + b'B'*8 + p64(win_addr)
# canary 자리에 leak한 값을 그대로 되돌려놔서 검사를 통과시킴
```

### 우회 2: byte-by-byte brute force (fork 서버 환경)

```
canary는 항상 첫 바이트가 0x00 (문자열 함수로 인한 조기 종료 방지 목적)
-> 65번째 바이트부터 한 바이트씩 0x00~0xff 넣어보며 crash 여부 확인
-> crash 안 나는 값 = 그 바이트의 정답 -> 다음 바이트로 이동
-> 8바이트 전부 복원 (평균 256*8/2 = 1024회 정도의 시도로 전체 canary 획득)
```

---

## 5. RELRO

### 예시 코드

c

```c
int main() {
    char buf[64];
    printf("Name: ");
    read(0, buf, 200);   // 오버플로우 + puts@got 덮어쓰기 가능하다고 가정
    puts(buf);
}
```

### No RELRO / Partial RELRO (적용 전)

```
.got.plt 영역 (쓰기 가능):
0x404018   puts@got   ->  원래는 puts() 실제 주소를 담고 있음

공격: 임의 쓰기 취약점으로 puts@got 값을 system() 주소로 덮어씀
0x404018   puts@got   ->  0x7f3a2c850740 (system 주소로 교체)

이후 코드에서 puts(buf) 호출 시
-> 실제로는 GOT를 거쳐 system(buf) 이 호출됨
-> buf에 "/bin/sh"를 넣어뒀다면 system("/bin/sh") 실행
```

GOT가 쓰기 가능한 메모리이기 때문에, 임의 주소 쓰기 취약점 하나만 있으면 원하는 함수 호출로 바꿔치기할 수 있습니다.

### Full RELRO (적용 후)

```
프로그램 시작 시점에 모든 심볼을 즉시 바인딩 완료 후:
mprotect(GOT 영역, PROT_READ)   // 쓰기 권한 제거

0x404018   puts@got   ->  read-only

같은 방식으로 puts@got 덮어쓰기 시도
-> 쓰기 권한 없는 메모리에 write 시도
-> SIGSEGV 발생
```

### 우회: GOT 대신 다른 함수 포인터 타겟팅

```
예: FILE 구조체의 vtable 포인터 조작 (_IO_FILE 계열)

정상 흐름:
fake_file->vtable->_IO_finish 등 함수 포인터를 통해 내부 함수 호출

공격:
1) 힙 취약점으로 stdout 구조체(_IO_FILE) 자체를 조작 가능하다고 가정
2) vtable 포인터를 공격자가 만든 가짜 vtable 주소로 교체
   real vtable: 0x7f3a2c9ed8c0
   fake vtable: 0x404060 (버퍼 안에 직접 구성한 가짜 테이블)
3) 그 안의 함수 포인터 슬롯에 원하는 함수(system 등) 주소를 배치
4) 다음 출력 함수 호출 시 fake vtable 경유 -> 임의 함수 실행

GOT는 read-only라 못 건드리지만, 힙에 있는 FILE 구조체 자체는
여전히 쓰기 가능한 경우가 많아 이쪽을 노리는 것 (FSOP 계열 공격)
```

---

## 종합: 5개 전부 켜진 경우 (실전 최다 케이스)

```
checksec 결과:
NX:        Enabled
PIE:       Enabled
Canary:    Enabled
RELRO:     Full

필요한 공격 체인 순서 (예시):
1. 포맷 스트링 등으로 canary leak      -> canary 값 획득
2. 같은 방식으로 코드 영역 주소 leak    -> PIE base 역산
3. GOT 등에서 libc 함수 주소 leak      -> libc base 역산
4. canary 자리 원상복구 + PIE/libc 오프셋 기반으로 ROP 체인 구성
5. RELRO가 Full이라 GOT는 못 건드리므로 __free_hook / _IO_FILE 등
   힙 기반 함수 포인터를 최종 타겟으로 선택
```
