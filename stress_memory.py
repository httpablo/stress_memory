import time
import sys

def run_stress_test():
    """
    Aloca blocos de memória em um loop para induzir o uso de swap.
    O programa continua até que o sistema não consiga mais alocar memória
    ou seja interrompido pelo usuário (Ctrl+C).
    """
    allocated_memory = []
    BLOCK_SIZE_BYTES = 100 * 1024 * 1024 
    
    print("--- INICIANDO TESTE DE ESTRESSE DE MEMÓRIA ---")
    print(f"Alocando memória em blocos de {BLOCK_SIZE_BYTES / (1024*1024):.0f} MB.")
    print("Pressione Ctrl+C para encerrar o teste a qualquer momento.")
    print("-" * 50)

    try:
        block_count = 0
        while True:
            block_count += 1
            print(f"[{time.strftime('%H:%M:%S')}] Alocando bloco {block_count}...", end="", flush=True)
            
            # 1. Aloca um bloco de memória
            new_block = bytearray(BLOCK_SIZE_BYTES)
            
            # 2. "Toca" na memória: escreve um byte para forçar a alocação física da página.
            new_block[0] = 0x01 
            
            # 3. Mantém uma referência ao bloco para evitar que o garbage collector o libere.
            allocated_memory.append(new_block)
            
            total_mb_allocated = len(allocated_memory) * (BLOCK_SIZE_BYTES / (1024*1024))
            print(f" SUCESSO. Total alocado: {total_mb_allocated:.0f} MB")
            
            # Pausa para permitir que as ferramentas de monitoramento capturem o estado do sistema.
            time.sleep(1)

    except MemoryError:
        print("\n" + "-" * 50)
        print("ERRO DE MEMÓRIA: O sistema operacional não pôde alocar mais memória.")
        print("Este é o ponto máximo de estresse alcançado.")
    except KeyboardInterrupt:
        print("\n" + "-" * 50)
        print("TESTE INTERROMPIDO PELO USUÁRIO.")
    finally:
        total_mb_allocated = len(allocated_memory) * (BLOCK_SIZE_BYTES / (1024*1024))
        print(f"Teste finalizado. Memória total que permaneceu alocada: {total_mb_allocated:.0f} MB.")
        print("--- FIM DO TESTE DE ESTRESSE ---")
        sys.exit(0)

if __name__ == "__main__":
    run_stress_test()
