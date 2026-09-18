#include <alsa/asoundlib.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>

#define TONE_HZ 400
#define SAMPLE_RATE 48000
#define CHANNELS 2
#define CYCLE_COUNT 100
#define FRAMES_PER_CYCLE (SAMPLE_RATE / TONE_HZ)
#define SAMPLE_FRAMES (CYCLE_COUNT * FRAMES_PER_CYCLE)
#define HALF_PERIOD (FRAMES_PER_CYCLE / 2)
#define HIGH_SAMPLE 24576
#define LOW_SAMPLE (-24576)

static void fill_tone(int16_t *samples)
{
    int frame;

    for (frame = 0; frame < SAMPLE_FRAMES; ++frame) {
        int16_t value = ((frame / HALF_PERIOD) & 1) ? LOW_SAMPLE : HIGH_SAMPLE;

        samples[frame * CHANNELS] = value;
        samples[frame * CHANNELS + 1] = value;
    }
}

int main(int argc, char **argv)
{
    const char *device = argc > 1 ? argv[1] : "hw:0,0";
    int16_t samples[SAMPLE_FRAMES * CHANNELS];
    snd_pcm_t *pcm = NULL;
    snd_pcm_sframes_t written;
    snd_pcm_uframes_t offset = 0;
    int status;

    fill_tone(samples);

    status = snd_pcm_open(&pcm, device, SND_PCM_STREAM_PLAYBACK, 0);
    if (status < 0) {
        fprintf(stderr, "snd_pcm_open(%s): %s\n", device, snd_strerror(status));
        return 10;
    }

    status = snd_pcm_set_params(pcm,
                                SND_PCM_FORMAT_S16_LE,
                                SND_PCM_ACCESS_RW_INTERLEAVED,
                                CHANNELS,
                                SAMPLE_RATE,
                                1,
                                500000);
    if (status < 0) {
        fprintf(stderr, "snd_pcm_set_params: %s\n", snd_strerror(status));
        snd_pcm_close(pcm);
        return 11;
    }

    while (offset < SAMPLE_FRAMES) {
        written = snd_pcm_writei(pcm,
                                 samples + offset * CHANNELS,
                                 SAMPLE_FRAMES - offset);
        if (written == -EPIPE) {
            status = snd_pcm_prepare(pcm);
            if (status < 0) {
                fprintf(stderr, "snd_pcm_prepare: %s\n", snd_strerror(status));
                snd_pcm_close(pcm);
                return 12;
            }
            continue;
        }
        if (written < 0) {
            fprintf(stderr, "snd_pcm_writei: %s\n", snd_strerror((int)written));
            snd_pcm_close(pcm);
            return 13;
        }
        offset += (snd_pcm_uframes_t)written;
    }

    status = snd_pcm_drain(pcm);
    if (status < 0) {
        fprintf(stderr, "snd_pcm_drain: %s\n", snd_strerror(status));
        snd_pcm_close(pcm);
        return 14;
    }

    snd_pcm_close(pcm);
    return 0;
}
