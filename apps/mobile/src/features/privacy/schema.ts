import { index, primaryKey, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const localBlock = sqliteTable(
	"local_block",
	{
		viewerId: text("viewer_id").notNull(),
		blockedUserId: text("blocked_user_id").notNull(),
		name: text("name").notNull(),
		image: text("image"),
		createdAt: text("created_at").notNull(),
	},
	(table) => [
		primaryKey({ columns: [table.viewerId, table.blockedUserId] }),
		index("local_block_viewer_id_idx").on(table.viewerId),
		index("local_block_blocked_user_id_idx").on(table.blockedUserId),
	],
);

export type LocalBlockRow = typeof localBlock.$inferSelect;
