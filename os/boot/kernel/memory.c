#include "memory.h"
#include "bitmap.h"
#include "global.h"
#include "debug.h"
#include "stdint.h"
#include "print.h"
#include "string.h"

#define PG_SIZE 4096

#define MEM_BITMAP_BASE 0xc009a000
#define K_HEAP_START 0xc0100000
#define PDE_IDX(addr) ((addr & 0xffc00000) >> 22)
#define PTE_IDX(addr) ((addr & 0x003ff000) >> 12)

struct pool
{
    struct bitmap pool_bitmap;
    uint32_t phy_addr_start;
    uint32_t pool_size;
};
struct pool kernel_pool, user_pool;
struct virtual_addr kernel_vadddr;

static void mem_pool_init(uint32_t all_mem){
    put_str("    mem_pool_init start\n");
    uint32_t page_table_size = PG_SIZE * 256;   // 1 MB 0x100000
    uint32_t used_mem = page_table_size + 0x100000; // 1MB + 1MB，已使用2MB空间
    // 前 1 MB 
    uint32_t free_mem = all_mem - used_mem; // 30MB
    uint16_t all_free_pages = free_mem / PG_SIZE; // 30MB / 4KB 约 7500 个

    uint16_t kernel_free_pages = all_free_pages / 2; // 各3750页
    uint16_t user_free_pages = all_free_pages - kernel_free_pages;

    // kernel 和 user bitmap 的长度
    uint32_t kbm_length = kernel_free_pages / 8; // 3750 / 8 = 468，1字节8位，管理8个页内存
    uint32_t ubm_length = user_free_pages / 8; // 这里就是位图的长度了

    uint32_t kp_start = used_mem;
    uint32_t up_start = kp_start + kernel_free_pages * PG_SIZE;

    kernel_pool.phy_addr_start = kp_start; // 内核堆空间从0x200000开始
    user_pool.phy_addr_start = up_start;   // 空户堆空间，在内核之后

    kernel_pool.pool_size = kernel_free_pages * PG_SIZE; // 内核空间和用户空间内存池大小
    user_pool.pool_size = user_free_pages * PG_SIZE;

    kernel_pool.pool_bitmap.btmp_bytes_len = kbm_length; // 内存池长度
    user_pool.pool_bitmap.btmp_bytes_len = ubm_length;

    kernel_pool.pool_bitmap.bits = (void *)MEM_BITMAP_BASE;   // 位图地址
    user_pool.pool_bitmap.bits = (void *)(MEM_BITMAP_BASE + kbm_length);

    put_str("        kernel_pool_bitmap_start:");
    put_int((int)kernel_pool.pool_bitmap.bits);
    put_str(" kernel_pool_phy_addr_start:");
    put_int(kernel_pool.phy_addr_start);
    put_str("\n");
    put_str("        user_pool_bitmap_start:");
    put_int((int)user_pool.pool_bitmap.bits);
    put_str(" user_pool_phy_addr_start:");
    put_int(user_pool.phy_addr_start);
    put_str("\n");

    bitmap_init(&kernel_pool.pool_bitmap);
    bitmap_init(&user_pool.pool_bitmap);

    kernel_vadddr.vaddr_bitmap.btmp_bytes_len = kbm_length;
    kernel_vadddr.vaddr_bitmap.bits = (void*)(MEM_BITMAP_BASE + kbm_length + ubm_length);

    kernel_vadddr.vaddr_start = K_HEAP_START;
    bitmap_init(&kernel_vadddr.vaddr_bitmap);

    put_str("    mem_pool_init done\n");
}

void mem_init(){
    put_str("mem_init start\n");
    uint32_t mem_bytes_total = (*(uint32_t*)(0xb00));
    mem_pool_init(mem_bytes_total);
    put_str("mem_init done\n");
}
static void page_table_add(void* _vaddr, void* _page_phyaddr){
    uint32_t vaddr = (uint32_t) _vaddr, page_phyaddr = (uint32_t) _page_phyaddr;
    uint32_t* pde = pde_ptr(vaddr);
    uint32_t* pte = pte_ptr(vaddr);

    if(*pde & 0x00000001){
        ASSERT(!(*pte & 0x00000001));
        if(!(*pte & 0x00000001)){
            *pte = (page_phyaddr | PG_US_U | PG_RW_W | PG_P_1);
        }else{
            PANIC("pte repeat");
            *pte = (page_phyaddr | PG_US_U | PG_RW_W | PG_P_1);
        }
    }else{
        uint32_t pde_phyaddr = (uint32_t) palloc(&kernel_pool);
        *pde  =(pde_phyaddr | PG_US_U | PG_RW_W | PG_P_1);

        memset((void*)((int)pte & 0xfffff000), 0, PG_SIZE);
        ASSERT(!(*pte & 0x00000001));
        *pte = (page_phyaddr | PG_US_U | PG_RW_W | PG_P_1);
    }
}

void* malloc_page(enum pool_flags pf, uint32_t pg_cnt){
    ASSERT(pg_cnt > 0 && pg_cnt < 3840);
    void* vaddr_start = vaddr_get(pf, pg_cnt);
    if(vaddr_start == NULL){
        return NULL;
    }

    uint32_t vaddr = (uint32_t) vaddr_start, cnt = pg_cnt;
    struct pool* mem_pool = pf & PF_KERNEL ? &kernel_pool : &user_pool;

    while(cnt-- > 0){
        void* page_phyaddr = palloc(mem_pool);
        if(page_phyaddr == NULL){
            return NULL;
        }
        page_table_add((void*) vaddr, page_phyaddr);
        vaddr += PG_SIZE;
    }
    return vaddr_start;
}

void* get_kernel_pages(uint32_t pg_cnt){
    void* vaddr = malloc_page(PF_KERNEL, pg_cnt);
    if(vaddr != NULL){
        memset(vaddr, 0, pg_cnt*PG_SIZE);
    }
    return vaddr;
}

static void* vaddr_get(enum pool_flags pf, uint32_t pg_cnt){
    int vaddr_start = 0, bit_idx_start = -1;
    uint32_t cnt = 0;
    if(pf == PF_KERNEL){ 
        //指定内核内存分配
        //首先找到一段连续的空间，页数满足pg_cnt，返回页数的下标
        bit_idx_start = bitmap_scan(&kernel_vadddr.vaddr_bitmap, pg_cnt);
        if(bit_idx_start == -1){
            return NULL;
        }
        while(cnt < pg_cnt){//找到后对应位图设置为已使用
            bitmap_set(&kernel_vadddr.vaddr_bitmap, bit_idx_start+cnt++, 1);
        }
        //返回能够分配的虚拟地址
        vaddr_start = kernel_vadddr.vaddr_start + bit_idx_start + PG_SIZE;
    }else{
        //用户内存分配
    }
    return (void*) vaddr_start;
}

uint32_t* pte_ptr(uint32_t vaddr){
    uint32_t* pte = (uint32_t*)(0xffc00000 + \
                    ((vaddr & 0xffc00000) >> 10) + \
                    PTE_IDX(vaddr) * 4);
    return pte;
}

uint32_t* pde_ptr(uint32_t vaddr){
    uint32_t* pde = (uint32_t*)((0xfffff000) + PDE_IDX(vaddr) * 4);
    return pde;
}

static void* palloc(struct pool* m_pool){
    int bit_idx = bitmap_scan(&m_pool->pool_bitmap, 1);
    if(bit_idx == -1){
        return NULL;
    }
    bitmap_set(&m_pool->pool_bitmap, bit_idx, 1);
    uint32_t page_phyaddr = ((bit_idx * PG_SIZE) + m_pool->phy_addr_start);
    return (void*) page_phyaddr;
}