---
title: "메모리 보호 기법(Mitigation)"
date: 2026-08-20 22:00:00 +0900
categories: [Security, Pwnable]
tags: [pwnable, binary-exploitation, nx, aslr, pie, stack-canary, relro, rop, mitigation]
published: true
---

리눅스 실행 파일(ELF)에는 다양한 메모리 보호 기법들이 적용되어 있다.
`checksec` 명령어를 사용하면 바이너리에 어떤 보호 기법이 적용되어 있는지 쉽게 확인할 수 있다.
이번 포스트에서는 대표적인 메모리 보호 기법 5가지를 알아보려고 한다.

```text
- stack canary
- nx
- aslr
- pie
- relro
```

이 기법들의 존재 이유, 역할, 그리고 이를 파훼할 수 있는 방법들에 대해 알아보자.

## 1. NX (No-eXecute) / DEP
### 존재 이유
초기 익스플로잇은 스택이나 힙에 셸코드를 직접 주입하고 그 주소로 리턴(점프)하여 바로 실행시키는 방식이었다. 메모리 영역이 "쓰기 가능 = 실행 가능"이었기 때문에 가능했던 공격이며, 이를 막기 위해 CPU에 하드웨어 비트(x86의 경우 NX bit, ARM은 XN bit)가 추가되면서 OS가 페이지 단위로 실행 권한을 제어할 수 있게 되었다.

### 보안 효과
스택, 힙 등 데이터 영역에 올린 셸코드는 실행 권한이 없으므로, 해당 영역으로 점프하더라도 SIGSEGV가 발생하며 프로그램이 강제 종료된다. 즉, "쓰기 가능한 메모리에 코드를 심고 실행"하는 가장 직관적인 공격 경로를 원천 차단한다.

### 파훼 방법
코드를 새로 심는 대신 이미 실행 권한이 있는 기존 코드(바이너리 자체 또는 libc)를 재사용하는 방식으로 우회한다.

- ret2libc: libc 내 함수(system 등)로 바로 리턴
- ROP (Return-Oriented Programming): 여러 gadget(ret으로 끝나는 짧은 명령어 조각)을 체이닝하여 임의 로직 구성
- ret2syscall / SROP: 시스템콜을 직접 조립해서 실행
- mmap으로 RWX(Read-Write-Execute) 메모리를 새로 할당받아 거기에 셸코드를 올리는 방식도 우회 범주에 들어간다. 이는 NX 자체를 뚫는 것이 아니라 "실행 가능한 새 메모리"를 합법적으로 확보하는 방식이라는 점이 핵심이다.

## 2. ASLR (Address Space Layout Randomization)
### 존재 이유
NX가 도입되면서 공격자들은 ret2libc나 ROP를 사용하기 시작했는데, 이 기법들은 정확한 함수나 gadget의 메모리 주소를 알아야만 동작한다. 바이너리와 라이브러리 로드 주소가 매번 고정되어 있다면 한 번 분석해서 얻은 주소를 계속 재사용할 수 있으므로, 이를 막기 위해 커널이 프로세스 실행 시마다 스택, 힙, mmap, 라이브러리 베이스 주소를 랜덤하게 배치하도록 만든 것이 ASLR이다.

### 보안 효과
공격자가 사전에 주소를 하드코딩하여 작성해 둔 익스플로잇 코드가 무력화된다. 정확한 주소를 모르면 ROP 체인도, ret2libc도 구성할 수 없다.

### 파훼 방법
"주소 하나를 leak(유출)해서 나머지를 오프셋으로 계산"하는 것이 핵심 대응이다.

- 포맷 스트링 버그로 스택/GOT 상의 포인터 값 직접 출력
- 함수 호출 결과(예: puts로 GOT 엔트리 출력)로 libc base 역산
- Partial RELRO 환경에서 GOT leak을 통한 libc base 계산
- 브루트포스 (단, 리눅스는 보통 하위 12비트 정도만 랜덤화되지 않아 완전 무작위는 아니지만, 64비트 환경에서는 이론상 가능할 뿐 비실용적임)

참고로 리눅스 ASLR은 스택, 힙, mmap(라이브러리 포함) 각각 독립적으로 적용된다. PIE가 꺼져있다면 바이너리 코드 자체는 랜덤화 대상에서 제외된다.

## 3. PIE (Position Independent Executable)
### 존재 이유
ASLR이 라이브러리와 스택/힙을 랜덤화하더라도, 바이너리 본체가 항상 같은 고정 주소(예: 0x400000)에 로드된다면 그 안의 함수, gadget, GOT 주소는 여전히 하드코딩이 가능했다. 공유 라이브러리처럼 실행 파일 자체도 상대주소 기반으로 컴파일하여 로드 시점에 임의 베이스 주소에 올라갈 수 있게 만든 것이 PIE다.

### 보안 효과
바이너리 내부의 모든 심볼(함수, 전역 변수, GOT/PLT 등) 주소가 실행 시마다 랜덤화된 베이스에 따라 바뀐다. ROPgadget 등으로 미리 뽑아둔 가젯 주소도 실제 실행 시엔 오프셋으로만 쓸모가 있으며, 런타임 베이스 주소를 모르면 무용지물이 된다.

### 파훼 방법
바이너리 내부 주소 하나를 leak하여 베이스 주소를 역산한다.

- 스택에 남아있는 리턴 주소(코드 세그먼트 내 주소)를 leak한 뒤, 저장된 오프셋을 빼서 base 계산
- 포맷 스트링 버그로 $rip 근처 스택 값을 직접 읽기
- GOT 엔트리 leak (RELRO 상태에 따라 난이도 상이)

종종 로컬에서 구한 "leak한 주소 - base"의 오프셋이 리모트 서버에서는 먹히지 않는 경우가 있는데, 이는 리모트 서버의 스택 레이아웃(환경변수, argv 차이 등)이 다르기 때문이다. PIE 자체의 문제라기보다는 leak 지점의 스택 프레임 구조가 로컬과 리모트에서 다르게 정렬되는 것이 진짜 원인인 경우가 많다.

## 4. Stack Canary (Stack Protector)
### 존재 이유
스택 버퍼 오버플로우를 이용해 지역 변수 버퍼 뒤에 있는 리턴 주소를 덮어써서 제어 흐름을 탈취하는 것은 가장 고전적인 공격 방식이다. 이를 컴파일러 단에서 방어하기 위해, 함수 진입 시 버퍼와 리턴 주소 사이에 랜덤 값을 심어두고 함수 종료 직전에 그 값이 그대로인지 검사하도록 만든 것이 canary다.

### 보안 효과
버퍼를 순차적으로 오버플로우시켜 리턴 주소까지 덮으려면 반드시 canary 값을 먼저 지나가야 한다. 정확한 값을 모르고 덮어쓰면 함수 리턴 시 __stack_chk_fail이 호출되어 프로세스가 즉시 강제 종료된다. 즉 "canary 값을 모르는 순차적 오버플로우"를 원천 차단한다.

### 파훼 방법

- Leak: 포맷 스트링 버그나 정보 노출 취약점으로 canary 값을 직접 읽어냄
- Byte-by-byte brute force: fork 서버 환경에서 canary의 첫 바이트가 항상 null byte(0x00)인 점을 이용해, 한 바이트씩 맞춰가며 crash 여부로 값을 추론
- 비순차적 덮어쓰기: 배열 인덱스 조작 등으로 canary 영역을 건너뛰고 리턴 주소만 직접 덮는 방법 (canary 검사 자체를 우회하므로 leak 불필요)

canary는 스레드마다 TLS(Thread Local Storage)에 저장되므로, 멀티스레드 환경에서는 TLS 자체를 조작하는 고급 기법도 존재한다.

## 5. RELRO (RELocation Read-Only)
### 존재 이유
동적 링킹 바이너리는 함수 호출 시 GOT(Global Offset Table)를 거쳐서 실제 라이브러리 함수 주소로 점프한다. lazy binding 방식에서는 GOT가 처음엔 PLT stub을 가리키다가 최초 호출 시점에 실제 주소로 채워지는데, 이 GOT 영역이 쓰기 가능한 상태로 남아있다 보니 공격자가 임의 쓰기(Arbitrary Write) 취약점으로 GOT 엔트리를 조작해 제어 흐름을 탈취하는 경로가 생겼다. 이를 막기 위해 GOT를 read-only로 만드는 보호 기법이 도입되었다.

### 보안 효과

- Partial RELRO: .got 등 일부 세그먼트만 read-only가 되고 .got.plt는 여전히 쓰기 가능하므로, GOT overwrite 공격이 여전히 가능하다.
- Full RELRO: 프로그램 시작 시 모든 심볼을 즉시 바인딩(eager binding)하고, 링킹이 끝난 뒤 GOT 전체를 read-only로 설정(mprotect)하므로 GOT overwrite 공격이 완전히 막힌다.

### 파훼 방법
Full RELRO 환경에서는 GOT를 수정할 수 없으므로 다른 쓰기 가능한 함수 포인터를 노려야 한다.

- __free_hook, __malloc_hook 등 힙 후킹 포인터 덮어쓰기
- _IO_FILE 구조체의 vtable 포인터 조작 (FSOP, House of Orange 계열)
- _rtld_global의 dl_load_write_ptr 등 링커 내부 구조체를 조작하여 리졸버 흐름 자체를 하이재킹
- Partial RELRO라면 기존처럼 GOT overwrite로 충분하다.

특히 최신 glibc(2.34+) 환경에서는 hook 함수 자체가 제거되었기 때문에, Full RELRO를 우회하기 위해 _IO_FILE이나 _rtld_global과 같은 내부 구조체를 조작하는 기법을 이해하는 것이 매우 중요해졌다.

## 바이너리 보호 기법: 적용 전/후 예시 비교
모든 주소와 값은 이해를 돕기 위한 가상의 예시다.

### 1. NX (No-eXecute)
**예시 코드**

```c
void vuln() {
    char buf[64];
    read(0, buf, 256);  // 버퍼 오버플로우 발생
}
```
**NX OFF (적용 전)**

```
스택 레이아웃 (vuln 함수 실행 중):
0x7ffee000  [ buf[64]           ]
0x7ffee040  [ saved rbp         ]
0x7ffee048  [ return address    ]  <- 여기를 shellcode 주소(0x7ffee000)로 덮음

결과: buf에 심어둔 shellcode가 정상적으로 실행됨 -> /bin/sh 획득
```

**NX ON (적용 후)**

```
동일한 payload로 0x7ffee000(buf)로 리턴 시도
-> buf가 존재하는 스택 페이지는 실행 권한(X)이 없음
-> SIGSEGV 발생, 프로세스 즉시 종료 (Segmentation fault)
```

**우회: ROP로 재구성**

```
공격 payload:
[ padding(72B) ]
+ pop rdi; ret;         (0x401234)
+ "/bin/sh\0" 문자열 주소 (0x402008)
+ system@plt 주소        (0x401050)

결과: buf가 아니라 이미 실행 권한이 있는 코드 영역(.text)의 gadget들만 재사용하여 실행 -> system("/bin/sh") 호출 성공
```

### 2. ASLR
**ASLR OFF (적용 전)**

```
$ ./vuln
libc base: 0x7ffff7dc0000   (항상 동일)
system():  0x7ffff7e10000   (항상 동일)
```

주소가 고정되어 있어 exploit 스크립트에 값을 하드코딩할 수 있다.

```python
payload = b'A'*72 + p64(0x7ffff7e10000)
```

**ASLR ON (적용 후)**

```
$ ./vuln
libc base: 0x7f3a2c800000   (실행마다 랜덤)

$ ./vuln
libc base: 0x7f3a91200000   (또 바뀜)
```
하드코딩된 주소로 점프하게 되면 엉뚱한 메모리를 참조하여 프로그램이 크래시된다.

**우회: leak 후 오프셋 계산**

```python

# 1) 취약점으로 GOT에 걸린 puts()의 실제 주소를 leak (매번 바뀜)
leaked_puts = 0x7f3a2c823020 

# 2) libc 내부에서 puts와 base 사이의 오프셋은 항상 고정
libc_base = leaked_puts - 0x823020   # 0x7f3a2c800000

# 3) system, "/bin/sh" 오프셋도 고정값이므로 base에 더해서 계산
system_addr = libc_base + 0x050740
binsh_addr  = libc_base + 0x1d8698
```

### 3. PIE
**예시 코드**

```c
void win() { system("/bin/sh"); }
void main() { vuln(); }
```

**PIE OFF (적용 전)**

```
$ objdump -d vuln
0000000000401196 <win>:   <- 항상 이 주소로 고정
```
바이너리가 0x400000대 고정 주소에 로드되므로 주소 하드코딩이 가능하다.

```python
payload = b'A'*72 + p64(0x401196) 
```

**PIE ON (적용 후)**

```
$ ./vuln
win() 실제 주소: 0x55a2b3401196   (베이스가 실행마다 랜덤)
```

**우회: 코드 영역 주소 leak → 베이스 역산**

```python
# 1) 스택에 남은 리턴 주소 등을 leak
leaked = 0x55a2b34011a5

# 2) objdump 등으로 미리 알아낸 해당 지점의 오프셋을 차감
pie_base = leaked - 0x11a5          # 0x55a2b3400000

# 3) win()의 오프셋을 base에 더해 실제 주소 계산
win_addr = pie_base + 0x1196        # 0x55a2b3401196
```

### 4. Stack Canary
**예시 코드**

```c
void vuln() {
    char buf[64];
    gets(buf);   // 경계 검사 없는 입력
}
```

**Canary 없음 (적용 전)**

```
스택 레이아웃: buf[64] -> saved rbp -> return address
payload = b'A'*72 + p64(win_addr)
결과: 별도의 검사 없이 그대로 win()으로 점프 성공
```

**Canary 있음 (적용 후)**

```
스택 레이아웃: buf[64] -> canary(8B) -> saved rbp -> return address
결과: 순차적으로 덮어쓰는 과정에서 canary 값이 변조됨. 
      함수 종료 시 원래의 canary 값과 비교하여 다르면 __stack_chk_fail() 호출 후 강제 종료.
```

**우회: Leak을 통한 복구**

```python
# 포맷 스트링 등으로 canary 값을 먼저 읽어냄
canary = leaked_value

# canary 자리에 leak한 값을 그대로 되돌려 놓아 검사 통과
payload = b'A'*64 + p64(canary) + b'B'*8 + p64(win_addr)
```

### 5. RELRO
**예시 코드**

```c
int main() {
    char buf[64];
    read(0, buf, 200);   // 오버플로우 + puts@got 덮어쓰기 가능 환경 가정
    puts(buf);
}
```

**Partial RELRO (적용 전)**

```
0x404018   puts@got   ->   원래는 puts() 실제 주소를 담고 있음
공격: 임의 쓰기 취약점으로 puts@got 값을 system() 주소로 덮어씀
결과: 이후 puts(buf) 호출 시, GOT를 경유하며 system(buf)가 실행됨
```

**Full RELRO (적용 후)**

```
프로그램 시작 시점에 모든 심볼 바인딩 완료 후 GOT 쓰기 권한 제거
-> puts@got를 덮어쓰려 하면 SIGSEGV 발생 (Segmentation fault)
```

**우회: GOT 대신 다른 함수 포인터 타겟팅**
Full RELRO 환경에서는 GOT 수정이 불가능하므로, _IO_FILE과 같이 쓰기 권한이 남아있는 힙/데이터 영역의 구조체를 조작하여 실행 흐름을 뺏는 방식(FSOP 등)을 활용한다.

### 종합: 5개 전부 켜진 경우 (실전 최다 케이스)

```
checksec 결과:
NX:        Enabled
PIE:       Enabled
Canary:    Enabled
RELRO:     Full

필요한 공격 체인 순서 (예시):
1. 포맷 스트링/OOB 등으로 canary 값 leak
2. 코드 영역 주소 leak -> PIE base 역산
3. 라이브러리 함수 주소 leak -> libc base 역산
4. canary 자리를 원상복구하며 PIE/libc 오프셋 기반으로 ROP 체인 구성
5. Full RELRO이므로 GOT 대신 _IO_FILE, 링커 내부 구조체 등 힙/데이터 기반 함수 포인터를 최종 타겟으로 설정하여 익스플로잇
```
