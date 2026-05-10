// Auto-generato con: supabase gen types typescript --project-id <id>
// Per ora definito manualmente; aggiornare dopo la creazione del progetto Supabase.

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          username: string;
          display_name: string | null;
          avatar_url: string | null;
          created_at: string;
        };
        Insert: Omit<Database["public"]["Tables"]["profiles"]["Row"], "created_at">;
        Update: Partial<Database["public"]["Tables"]["profiles"]["Insert"]>;
      };
      books: {
        Row: {
          id: string;
          user_id: string;
          title: string;
          author: string;
          imported_at: string;
          cover_color: string;
        };
        Insert: Omit<Database["public"]["Tables"]["books"]["Row"], "id" | "imported_at">;
        Update: Partial<Database["public"]["Tables"]["books"]["Insert"]>;
      };
      highlights: {
        Row: {
          id: string;
          user_id: string;
          book_id: string;
          content: string;
          location: string | null;
          added_at: string | null;
          personal_note: string | null;
          content_hash: string;
          last_shown_in_widget: string | null;
          created_at: string;
        };
        Insert: Omit<
          Database["public"]["Tables"]["highlights"]["Row"],
          "id" | "created_at"
        >;
        Update: Partial<Database["public"]["Tables"]["highlights"]["Insert"]>;
      };
      jams: {
        Row: {
          id: string;
          owner_id: string;
          title: string;
          description: string | null;
          book_filter: string | null;
          invite_code: string;
          is_active: boolean;
          created_at: string;
        };
        Insert: Omit<Database["public"]["Tables"]["jams"]["Row"], "id" | "created_at" | "invite_code">;
        Update: Partial<Database["public"]["Tables"]["jams"]["Insert"]>;
      };
      jam_members: {
        Row: {
          jam_id: string;
          user_id: string;
          joined_at: string;
        };
        Insert: Omit<Database["public"]["Tables"]["jam_members"]["Row"], "joined_at">;
        Update: never;
      };
      jam_highlights: {
        Row: {
          jam_id: string;
          highlight_id: string;
          shared_by: string;
          shared_at: string;
        };
        Insert: Omit<Database["public"]["Tables"]["jam_highlights"]["Row"], "shared_at">;
        Update: never;
      };
      clippings_imports: {
        Row: {
          id: string;
          user_id: string;
          file_path: string | null;
          status: "pending" | "processing" | "done" | "error";
          error_message: string | null;
          books_added: number;
          highlights_added: number;
          duplicates_skipped: number;
          imported_at: string;
        };
        Insert: Pick<
          Database["public"]["Tables"]["clippings_imports"]["Row"],
          "user_id" | "file_path"
        >;
        Update: Partial<
          Omit<Database["public"]["Tables"]["clippings_imports"]["Row"], "id" | "user_id">
        >;
      };
    };
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: Record<string, never>;
  };
}

// Convenience types
export type Book = Database["public"]["Tables"]["books"]["Row"];
export type Highlight = Database["public"]["Tables"]["highlights"]["Row"];
export type Jam = Database["public"]["Tables"]["jams"]["Row"];
export type JamMember = Database["public"]["Tables"]["jam_members"]["Row"];
export type Profile = Database["public"]["Tables"]["profiles"]["Row"];
