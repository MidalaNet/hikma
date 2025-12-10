namespace MD4C {
	[CCode (cname = "md_parse")]
	public int parse (string text, size_t size, void* userdata,
		[CCode (cname = "MD_PARSER", has_type_id = false)] Parser* parser);

	[CCode (cname = "MD_PARSER", has_type_id = false)]
	public struct Parser {
		public uint abi_version;
		public uint flags;
		public void* renderer;
		public int (*enter_block) (void* userdata, int block_type, void* detail);
		public int (*leave_block) (void* userdata, int block_type, void* detail);
		public int (*enter_span)  (void* userdata, int span_type, void* detail);
		public int (*leave_span)  (void* userdata, int span_type, void* detail);
		public int (*text)        (void* userdata, int text_type, char* data, size_t size);
		public int (*debug_log)   (void* userdata, char* msg);
	}

	public const uint MD_FLAG_COLLAPSEWHITESPACE;
	public const uint MD_FLAG_PERMISSIVEURLAUTOLINKS;
	public const uint MD_FLAG_PERMISSIVEEMAILAUTOLINKS;
	public const uint MD_FLAG_TABLES;
}
