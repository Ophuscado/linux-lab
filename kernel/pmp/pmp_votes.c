// SPDX-License-Identifier: GPL-2.0-only
/*
 * pmp_votes: the PMP report's request words on the M2 Ultra (t6022), beyond the one word Linux's pmp-report drives.
 *
 * The report's SOC-DEV-PS-REQ field is 8 words (ADT iop-pmp-nub ptd-range: offset 0x200, size 8; read side
 * 16 bytes a word from 0x2000, write side 8 bytes a word from 0x11000; SOC-DEV-PS-ACK follows at 0x2080). The
 * nub's soc-device table gives die 1's devices die 0's IDs plus 64 (AVD1 82 = AVD0 18 + 64, DISPEXT4 79 =
 * DISPEXT0 15 + 64, IOA11/12 94/95 = IOA4/5 30/31 + 64), and a device's bit is its ID - 1, so die 1 votes in word
 * 1 with die 0's layout. pmp-report (drivers/pmdomain/apple/pmp-report.c) reads and writes word 0 only.
 *
 *   insmod pmp_votes.ko          read only: print every request and acknowledge word and the status word
 *   insmod pmp_votes.ko die1=1   also set in word 1 what pmp-report keeps on in word 0 for die 0, for die 1:
 *                                bit 14 (DISPEXT4, the HDMI port's DCP), 29 and 30 (IOA11, IOA12); the PMP's
 *                                acknowledgement is awaited only when it is running
 *   echo 1 > /sys/module/pmp_votes/parameters/dump
 *                                print the words again (kernel/pmp.sh dump)
 *   rmmod pmp_votes              word 1 back to what it was at load
 *
 * Word 1 is a register of its own, so writing it cannot race pmp-report's read-modify-write of word 0.
 */
#include <linux/bits.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>

#define REQ_RD(n)	(0x2000 + 16 * (n))
#define REQ_WR(n)	(0x11000 + 8 * (n))
#define ACK_RD(n)	(0x2080 + 16 * (n))
#define STATUS		0x10
#define PMP_READY	BIT_ULL(0)
#define WORDS		8
#define DIE1_ON		(BIT_ULL(14) | BIT_ULL(29) | BIT_ULL(30))

static bool die1;
module_param(die1, bool, 0444);
MODULE_PARM_DESC(die1, "set die 1's display and fabric votes in word 1 (default: read only)");

static void __iomem *base;
static u64 word1_at_load;
static bool changed;
static void show(const char *when);

static int dump_set(const char *val, const struct kernel_param *kp)
{
	if (base)	/* NULL while insmod parses its arguments */
		show("on request");
	return 0;
}

static const struct kernel_param_ops dump_ops = { .set = dump_set };
module_param_cb(dump, &dump_ops, NULL, 0200);
MODULE_PARM_DESC(dump, "write anything: print the words again");

static void show(const char *when)
{
	int n;

	pr_info("pmp_votes: %s: status %016llx\n", when, readq(base + STATUS));
	for (n = 0; n < WORDS; n++)
		pr_info("pmp_votes: %s: word %d req %016llx (+8: %016llx) ack %016llx (+8: %016llx)\n", when, n,
			readq(base + REQ_RD(n)), readq(base + REQ_RD(n) + 8), readq(base + ACK_RD(n)),
			readq(base + ACK_RD(n) + 8));
}

static int set_word1(u64 val)
{
	u64 ack;

	writeq(val, base + REQ_WR(1));
	if (readq(base + REQ_RD(1)) != val) {
		pr_err("pmp_votes: word 1 reads %016llx after writing %016llx (+8 reads %016llx): the layout is not what this module assumes\n",
		       readq(base + REQ_RD(1)), val, readq(base + REQ_RD(0) + 8));
		return -EIO;
	}
	if (!(readq(base + STATUS) & PMP_READY))
		return 0;	/* nobody to acknowledge yet: the PMP reads the word when it starts */
	return readq_poll_timeout(base + ACK_RD(1), ack, (ack & DIE1_ON) == (val & DIE1_ON), 100, 50000);
}

static int __init pmp_votes_init(void)
{
	struct device_node *np;
	struct resource res;
	int ret;

	if (!of_machine_is_compatible("apple,t6022"))
		return -ENODEV;	/* the offsets and bits are this SoC's */
	np = of_find_compatible_node(NULL, NULL, "apple,t6020-pmp-v2-report");
	if (!np)
		return -ENODEV;
	ret = of_address_to_resource(np, 0, &res);
	of_node_put(np);
	if (ret)
		return ret;
	if (resource_size(&res) < REQ_WR(WORDS))
		return -EINVAL;
	base = ioremap(res.start, resource_size(&res));	/* pmp-report holds the region; this maps it again */
	if (!base)
		return -ENOMEM;
	show("at load");
	if (!die1)
		return 0;

	word1_at_load = readq(base + REQ_RD(1));
	ret = set_word1(word1_at_load | DIE1_ON);
	if (ret) {
		writeq(word1_at_load, base + REQ_WR(1));
		show("refused, word 1 put back");
		iounmap(base);
		return ret;
	}
	changed = true;
	show("die 1 votes set");
	return 0;
}

static void __exit pmp_votes_exit(void)
{
	if (changed) {
		int ret = set_word1(word1_at_load);

		pr_info("pmp_votes: word 1 put back to %016llx%s\n", word1_at_load,
			ret ? " (no acknowledgement within 50 ms)" : "");
	}
	show("at unload");
	iounmap(base);
}

module_init(pmp_votes_init);
module_exit(pmp_votes_exit);
MODULE_DESCRIPTION("The t6022 PMP report's request words beyond word 0");
MODULE_LICENSE("GPL");
