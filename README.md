# Análise Experimental da Política de Swap no Linux

Este repositório contém os artefatos experimentais desenvolvidos para o artigo acadêmico sobre o gerenciamento de memória em Sistemas Operacionais, focado na análise do impacto do parâmetro `vm.swappiness` no Kernel Linux.

O principal componente deste repositório é o script `stress_memory.py`, uma ferramenta desenvolvida para induzir estresse de memória em um ambiente controlado e permitir a observação do mecanismo de swap.

## Sobre o Script `stress_memory.py`

O script `stress_memory.py` é uma aplicação em Python projetada para um único propósito: alocar memória de forma contínua e intensiva até que a RAM física do sistema se esgote. Seu funcionamento é simples:

1.  O programa entra em um loop infinito.
2.  A cada segundo, ele aloca um bloco de 100 MB de memória RAM.
3.  Crucialmente, ele "toca" em cada bloco alocado (escrevendo um byte), forçando o sistema operacional a alocar páginas de memória física reais, em vez de apenas mapear memória virtual (um comportamento conhecido como _lazy allocation_).
4.  O script mantém uma referência a todos os blocos alocados para impedir que o _garbage collector_ os libere.
5.  O processo continua até que o sistema não consiga mais alocar memória (gerando um `MemoryError`) ou seja interrompido manualmente (`Ctrl+C`).

Este comportamento foi projetado para forçar o sistema a um estado de pressão de memória, ativando o mecanismo de swap e permitindo a coleta de dados sobre o fenômeno do _thrashing_.

## Ambiente Experimental

Para garantir a reprodutibilidade dos resultados apresentados no artigo, o seguinte ambiente de máquina virtual (VM) foi utilizado:

- **Virtualizador:** Oracle VM VirtualBox
- **Sistema Operacional:** Ubuntu Server 22.04 LTS
- **Memória RAM Física:** 2 GB
- **Espaço de Swap:** 2 GB
- **CPU:** 1 vCPU

## Pré-requisitos

Para executar os experimentos, o ambiente necessita das seguintes ferramentas, que geralmente já vêm instaladas em distribuições Linux modernas:

- Python 3
- `sysstat` (pacote que contém `iostat`)
- `procps` (pacote que contém `vmstat` e `free`)

Caso o `sysstat` não esteja instalado, ele pode ser adicionado com o comando:

```bash
sudo apt update && sudo apt install sysstat
```

## Protocolo de Execução dos Experimentos

O protocolo a seguir deve ser executado para cada um dos três cenários avaliados no artigo (`swappiness` = 10, 60 e 100). É necessário reiniciar a VM entre cada experimento para garantir um estado inicial limpo.

**Setup:** Conecte-se à VM usando **três terminais SSH** simultaneamente.

---

### **Experimento (Exemplo para `swappiness=60`)**

1.  **Preparação (Terminal de Controle):**

    - Certifique-se de que a VM foi reiniciada.
    - Defina o valor do `swappiness` (requer privilégios de administrador). Para o cenário padrão, este passo não é necessário se o valor já for 60.
      ```bash
      sudo sysctl vm.swappiness=60
      ```
    - Confirme a alteração:
      ```bash
      cat /proc/sys/vm/swappiness
      ```

2.  **Início dos Monitores:**

    - **No Terminal 1 (Monitor `vmstat`):** Inicie o monitoramento da memória e do swap, redirecionando a saída para um arquivo de log.
      ```bash
      vmstat 1 > vmstat_log_swappiness_60.txt
      ```
    - **No Terminal 2 (Monitor `iostat`):** Inicie o monitoramento da atividade de E/S do disco. (Assumindo que o disco principal é `sda`).
      ```bash
      iostat -d sda 1 > iostat_log_swappiness_60.txt
      ```

3.  **Execução do Teste de Estresse:**

    - **No Terminal 3 (Execução do Script):** Execute o script `stress_memory.py` com o comando `time` para medir a duração total.
      ```bash
      time python3 stress_memory.py > output_swappiness_60.txt
      ```
    - Aguarde a execução terminar. O script irá parar automaticamente ao esgotar a memória.

4.  **Encerramento:**
    - Após o término do script no Terminal 3, volte para o Terminal 1 e pressione `Ctrl+C` para parar o `vmstat`.
    - Volte para o Terminal 2 e pressione `Ctrl+C` para parar o `iostat`.

---

### **Resultados Gerados**

Ao final de cada execução, os seguintes arquivos serão gerados na pasta `home` do usuário na VM:

- `output_swappiness_XX.txt`: Log de alocação do script de estresse.
- `vmstat_log_swappiness_XX.txt`: Registro segundo a segundo da atividade de memória e swap.
- `iostat_log_swappiness_XX.txt`: Registro segundo a segundo da atividade de E/S do disco.
