class_name HashUtil
extends RefCounted
## HashUtil.gd — hachage SHA1 partagé (identité des parties, event_id, drill_id).
## Source unique : évite la dérive entre plusieurs implémentations dispersées.

static func sha1_hex(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()
