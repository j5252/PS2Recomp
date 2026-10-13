// Minimal PS2 homebrew used to validate the recompile -> Raspberry Pi pipeline.
// Draws a sprite bouncing over a background whose color cycles, via gsKit.
// Build with the ps2dev toolchain: make -C rpi/samples/hello

#include <stdio.h>
#include <gsKit.h>
#include <dmaKit.h>

#define SPRITE_SIZE 64

int main(void)
{
    GSGLOBAL *gs = gsKit_init_global();
    gs->PSM = GS_PSM_CT24;
    gs->ZBuffering = GS_SETTING_OFF;

    dmaKit_init(D_CTRL_RELE_OFF, D_CTRL_MFD_OFF, D_CTRL_STS_UNSPEC,
                D_CTRL_STD_OFF, D_CTRL_RCYC_8, 1 << DMA_CHANNEL_GIF);
    dmaKit_chan_init(DMA_CHANNEL_GIF);

    gsKit_init_screen(gs);
    gsKit_mode_switch(gs, GS_ONESHOT);

    printf("ps2x hello: %dx%d\n", gs->Width, gs->Height);

    int x = 0, y = 0, dx = 3, dy = 2;
    unsigned int frame = 0;

    for (;;)
    {
        unsigned char r = (unsigned char)(frame & 0xFF);
        unsigned char g = (unsigned char)((frame * 2) & 0xFF);
        gsKit_clear(gs, GS_SETREG_RGBAQ(r, g, 0x40, 0x80, 0x00));

        gsKit_prim_sprite(gs, (float)x, (float)y,
                          (float)(x + SPRITE_SIZE), (float)(y + SPRITE_SIZE),
                          1, GS_SETREG_RGBAQ(0xFF, 0xFF, 0xFF, 0x80, 0x00));

        x += dx;
        y += dy;
        if (x < 0 || x + SPRITE_SIZE > gs->Width)
            dx = -dx;
        if (y < 0 || y + SPRITE_SIZE > gs->Height)
            dy = -dy;

        if ((frame % 60) == 0)
            printf("ps2x hello: frame %u\n", frame);

        gsKit_queue_exec(gs);
        gsKit_sync_flip(gs);
        frame++;
    }

    return 0;
}
