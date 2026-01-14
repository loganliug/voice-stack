```bash
# 查看 RT 调度
cat /proc/sys/kernel/sched_rt_runtime_us
# 在每 1 秒（1,000,000 µs） 的周期里, 实时线程最多只能跑 950 ms
950000
# 不限制
=1

# 验证调度调度
chrt -p $(pidof jackd)
pid 792's current scheduling policy: SCHED_RR
pid 792's current scheduling priority: 80

# 确认 ALSA 设备被 JACK 独占
sudo fuser -v /dev/snd/*
                     USER        PID ACCESS COMMAND
/dev/snd/controlC0:  root      44424 F.... jackd
/dev/snd/pcmC0D0c:   root      44424 F...m jackd
/dev/snd/pcmC0D0p:   root      44424 F...m jackd

# 看 JACK 启动日志是还有 RT 警告
journalctl -u jackd.service -b | grep -i rt

# 或直接让你 ASR / 音频处理程序跑起来，观察：
journalctl -u jackd.service -f

# XRUN 压力测试（运行几分钟）
jack_iodelay

# 扬声器发声：
sudo gst-launch-1.0 audiotestsrc ! audioresample ! jackaudiosink

```

## systemd

| 配置                          | 作用            |
| --------------------------- | --------------- | 
| `LimitRTPRIO`               | 允许 RT 优先级    |
| `LimitMEMLOCK`              | 允许 mlockall    |
| `CPUSchedulingPolicy=rr`    | systemd 层 RT   |
| `-R -P 80`                  | JACK 自身 RT     |
| `JACK_NO_AUDIO_RESERVATION` | 避免 dbus        |
| `Nice=-10`                  | 避免 systemd 降权 |


## 绑定 CPU，进一步降低抖动
如果你在 RK3588 / Orange Pi 这类多核 SoC 上，下一步可以：
让 jackd 跑在 独立 CPU
把 ASR / DSP 跑在另外的核
例如（可选）：
CPUAffinity=2