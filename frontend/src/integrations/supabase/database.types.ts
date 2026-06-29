export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      audit_log: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          entity_id: string | null
          entity_type: string
          id: string
          ip_address: string | null
          metadata: Json
          owner_id: string | null
          user_agent: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type: string
          id?: string
          ip_address?: string | null
          metadata?: Json
          owner_id?: string | null
          user_agent?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string
          id?: string
          ip_address?: string | null
          metadata?: Json
          owner_id?: string | null
          user_agent?: string | null
        }
        Relationships: []
      }
      audit_logs: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          details: Json | null
          entity: string | null
          entity_id: string | null
          id: string
          ip_address: string | null
          office_id: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          details?: Json | null
          entity?: string | null
          entity_id?: string | null
          id?: string
          ip_address?: string | null
          office_id?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          details?: Json | null
          entity?: string | null
          entity_id?: string | null
          id?: string
          ip_address?: string | null
          office_id?: string | null
        }
        Relationships: []
      }
      cases: {
        Row: {
          appeal_deadline: string | null
          assigned_employee_id: string | null
          case_number: string
          case_type: Database["public"]["Enums"]["case_type"]
          circuit_number: string | null
          client_id: string | null
          closed_at: string | null
          court: string | null
          created_at: string
          description: string | null
          id: string
          najiz_id: string | null
          najiz_synced_at: string | null
          opened_at: string
          owner_id: string
          status: Database["public"]["Enums"]["case_status"]
          title: string
          updated_at: string
        }
        Insert: {
          appeal_deadline?: string | null
          assigned_employee_id?: string | null
          case_number: string
          case_type?: Database["public"]["Enums"]["case_type"]
          circuit_number?: string | null
          client_id?: string | null
          closed_at?: string | null
          court?: string | null
          created_at?: string
          description?: string | null
          id?: string
          najiz_id?: string | null
          najiz_synced_at?: string | null
          opened_at?: string
          owner_id: string
          status?: Database["public"]["Enums"]["case_status"]
          title: string
          updated_at?: string
        }
        Update: {
          appeal_deadline?: string | null
          assigned_employee_id?: string | null
          case_number?: string
          case_type?: Database["public"]["Enums"]["case_type"]
          circuit_number?: string | null
          client_id?: string | null
          closed_at?: string | null
          court?: string | null
          created_at?: string
          description?: string | null
          id?: string
          najiz_id?: string | null
          najiz_synced_at?: string | null
          opened_at?: string
          owner_id?: string
          status?: Database["public"]["Enums"]["case_status"]
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "cases_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      client_inquiries: {
        Row: {
          author_id: string
          author_role: string
          body: string
          case_id: string | null
          client_id: string
          created_at: string
          id: string
          owner_id: string
          parent_id: string | null
          read_at: string | null
          status: string
          subject: string | null
        }
        Insert: {
          author_id: string
          author_role: string
          body: string
          case_id?: string | null
          client_id: string
          created_at?: string
          id?: string
          owner_id: string
          parent_id?: string | null
          read_at?: string | null
          status?: string
          subject?: string | null
        }
        Update: {
          author_id?: string
          author_role?: string
          body?: string
          case_id?: string | null
          client_id?: string
          created_at?: string
          id?: string
          owner_id?: string
          parent_id?: string | null
          read_at?: string | null
          status?: string
          subject?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "client_inquiries_case_id_fkey"
            columns: ["case_id"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_inquiries_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_inquiries_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "client_inquiries"
            referencedColumns: ["id"]
          },
        ]
      }
      client_notifications: {
        Row: {
          case_id: string | null
          channel: Database["public"]["Enums"]["notification_channel"]
          client_id: string | null
          created_at: string
          error_message: string | null
          id: string
          message: string
          owner_id: string
          scheduled_at: string | null
          sent_at: string | null
          status: Database["public"]["Enums"]["notification_status"]
          template: string | null
          updated_at: string
        }
        Insert: {
          case_id?: string | null
          channel?: Database["public"]["Enums"]["notification_channel"]
          client_id?: string | null
          created_at?: string
          error_message?: string | null
          id?: string
          message: string
          owner_id: string
          scheduled_at?: string | null
          sent_at?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          template?: string | null
          updated_at?: string
        }
        Update: {
          case_id?: string | null
          channel?: Database["public"]["Enums"]["notification_channel"]
          client_id?: string | null
          created_at?: string
          error_message?: string | null
          id?: string
          message?: string
          owner_id?: string
          scheduled_at?: string | null
          sent_at?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          template?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_notifications_case_id_fkey"
            columns: ["case_id"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "client_notifications_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      client_portal_credentials: {
        Row: {
          client_id: string
          created_at: string
          owner_id: string
          portal_access_code: string | null
          updated_at: string
        }
        Insert: {
          client_id: string
          created_at?: string
          owner_id: string
          portal_access_code?: string | null
          updated_at?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          owner_id?: string
          portal_access_code?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_portal_credentials_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: true
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      clients: {
        Row: {
          address: string | null
          created_at: string
          email: string | null
          full_name: string
          id: string
          id_number: string | null
          national_id: string | null
          notes: string | null
          owner_id: string
          phone: string | null
          portal_access_code: string | null
          portal_user_id: string | null
          updated_at: string
        }
        Insert: {
          address?: string | null
          created_at?: string
          email?: string | null
          full_name: string
          id?: string
          id_number?: string | null
          national_id?: string | null
          notes?: string | null
          owner_id: string
          phone?: string | null
          portal_access_code?: string | null
          portal_user_id?: string | null
          updated_at?: string
        }
        Update: {
          address?: string | null
          created_at?: string
          email?: string | null
          full_name?: string
          id?: string
          id_number?: string | null
          national_id?: string | null
          notes?: string | null
          owner_id?: string
          phone?: string | null
          portal_access_code?: string | null
          portal_user_id?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      document_permissions: {
        Row: {
          case_id: string | null
          created_at: string
          id: string
          owner_id: string
          permission: Database["public"]["Enums"]["doc_permission"]
          user_id: string
        }
        Insert: {
          case_id?: string | null
          created_at?: string
          id?: string
          owner_id: string
          permission?: Database["public"]["Enums"]["doc_permission"]
          user_id: string
        }
        Update: {
          case_id?: string | null
          created_at?: string
          id?: string
          owner_id?: string
          permission?: Database["public"]["Enums"]["doc_permission"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_permissions_case_id_fkey"
            columns: ["case_id"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
        ]
      }
      documents: {
        Row: {
          appeal_deadline: string | null
          case_id: string | null
          circuit_number: string | null
          court: string | null
          created_at: string
          description: string | null
          doc_type: Database["public"]["Enums"]["document_type"]
          file_name: string | null
          file_size: number | null
          filed_date: string | null
          id: string
          judgment_date: string | null
          mime_type: string | null
          owner_id: string
          storage_path: string | null
          title: string
          updated_at: string
        }
        Insert: {
          appeal_deadline?: string | null
          case_id?: string | null
          circuit_number?: string | null
          court?: string | null
          created_at?: string
          description?: string | null
          doc_type?: Database["public"]["Enums"]["document_type"]
          file_name?: string | null
          file_size?: number | null
          filed_date?: string | null
          id?: string
          judgment_date?: string | null
          mime_type?: string | null
          owner_id: string
          storage_path?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          appeal_deadline?: string | null
          case_id?: string | null
          circuit_number?: string | null
          court?: string | null
          created_at?: string
          description?: string | null
          doc_type?: Database["public"]["Enums"]["document_type"]
          file_name?: string | null
          file_size?: number | null
          filed_date?: string | null
          id?: string
          judgment_date?: string | null
          mime_type?: string | null
          owner_id?: string
          storage_path?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "documents_case_id_fkey"
            columns: ["case_id"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_messages: {
        Row: {
          attachment_url: string | null
          body: string
          created_at: string
          id: string
          is_read: boolean
          owner_id: string
          read_at: string | null
          recipient_id: string
          sender_id: string
          subject: string | null
        }
        Insert: {
          attachment_url?: string | null
          body: string
          created_at?: string
          id?: string
          is_read?: boolean
          owner_id: string
          read_at?: string | null
          recipient_id: string
          sender_id: string
          subject?: string | null
        }
        Update: {
          attachment_url?: string | null
          body?: string
          created_at?: string
          id?: string
          is_read?: boolean
          owner_id?: string
          read_at?: string | null
          recipient_id?: string
          sender_id?: string
          subject?: string | null
        }
        Relationships: []
      }
      employee_portal_credentials: {
        Row: {
          created_at: string
          employee_id: string
          owner_id: string
          portal_access_code: string | null
          portal_username: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          employee_id: string
          owner_id: string
          portal_access_code?: string | null
          portal_username?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          employee_id?: string
          owner_id?: string
          portal_access_code?: string | null
          portal_username?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_portal_credentials_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: true
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
        ]
      }
      employees: {
        Row: {
          assigned_cases: string[] | null
          assigned_clients: string[] | null
          created_at: string
          department: string | null
          direct_manager_id: string | null
          email: string | null
          end_date: string | null
          full_name: string
          id: string
          id_number: string | null
          is_active: boolean
          job_title: string | null
          national_id: string | null
          nationality: string | null
          owner_id: string
          permissions: Json | null
          phone: string | null
          portal_access_code: string | null
          portal_user_id: string | null
          portal_username: string | null
          position: string | null
          qualification: string | null
          residence_expiry: string | null
          start_date: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          assigned_cases?: string[] | null
          assigned_clients?: string[] | null
          created_at?: string
          department?: string | null
          direct_manager_id?: string | null
          email?: string | null
          end_date?: string | null
          full_name: string
          id?: string
          id_number?: string | null
          is_active?: boolean
          job_title?: string | null
          national_id?: string | null
          nationality?: string | null
          owner_id: string
          permissions?: Json | null
          phone?: string | null
          portal_access_code?: string | null
          portal_user_id?: string | null
          portal_username?: string | null
          position?: string | null
          qualification?: string | null
          residence_expiry?: string | null
          start_date?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          assigned_cases?: string[] | null
          assigned_clients?: string[] | null
          created_at?: string
          department?: string | null
          direct_manager_id?: string | null
          email?: string | null
          end_date?: string | null
          full_name?: string
          id?: string
          id_number?: string | null
          is_active?: boolean
          job_title?: string | null
          national_id?: string | null
          nationality?: string | null
          owner_id?: string
          permissions?: Json | null
          phone?: string | null
          portal_access_code?: string | null
          portal_user_id?: string | null
          portal_username?: string | null
          position?: string | null
          qualification?: string | null
          residence_expiry?: string | null
          start_date?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employees_direct_manager_id_fkey"
            columns: ["direct_manager_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
        ]
      }
      executions: {
        Row: {
          amount: number | null
          case_id: string | null
          client_id: string | null
          court: string | null
          created_at: string
          debtor_name: string | null
          execution_number: string
          filed_date: string | null
          id: string
          najiz_id: string | null
          najiz_synced_at: string | null
          notes: string | null
          owner_id: string
          status: Database["public"]["Enums"]["execution_status"]
          updated_at: string
        }
        Insert: {
          amount?: number | null
          case_id?: string | null
          client_id?: string | null
          court?: string | null
          created_at?: string
          debtor_name?: string | null
          execution_number: string
          filed_date?: string | null
          id?: string
          najiz_id?: string | null
          najiz_synced_at?: string | null
          notes?: string | null
          owner_id: string
          status?: Database["public"]["Enums"]["execution_status"]
          updated_at?: string
        }
        Update: {
          amount?: number | null
          case_id?: string | null
          client_id?: string | null
          court?: string | null
          created_at?: string
          debtor_name?: string | null
          execution_number?: string
          filed_date?: string | null
          id?: string
          najiz_id?: string | null
          najiz_synced_at?: string | null
          notes?: string | null
          owner_id?: string
          status?: Database["public"]["Enums"]["execution_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "executions_case_id_fkey"
            columns: ["case_id"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "executions_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      najiz_sync_logs: {
        Row: {
          created_at: string
          error_message: string | null
          id: string
          inserted_count: number | null
          items_count: number | null
          kind: string
          owner_id: string
          raw_payload: Json | null
          source: string
          status: string
          trace: Json | null
          updated_count: number | null
        }
        Insert: {
          created_at?: string
          error_message?: string | null
          id?: string
          inserted_count?: number | null
          items_count?: number | null
          kind: string
          owner_id: string
          raw_payload?: Json | null
          source?: string
          status?: string
          trace?: Json | null
          updated_count?: number | null
        }
        Update: {
          created_at?: string
          error_message?: string | null
          id?: string
          inserted_count?: number | null
          items_count?: number | null
          kind?: string
          owner_id?: string
          raw_payload?: Json | null
          source?: string
          status?: string
          trace?: Json | null
          updated_count?: number | null
        }
        Relationships: []
      }
      notification_preferences: {
        Row: {
          appeals: Json
          channels: Json
          created_at: string
          id: string
          owner_id: string
          quiet_hours: Json
          sessions: Json
          tasks: Json
          updated_at: string
        }
        Insert: {
          appeals?: Json
          channels?: Json
          created_at?: string
          id?: string
          owner_id: string
          quiet_hours?: Json
          sessions?: Json
          tasks?: Json
          updated_at?: string
        }
        Update: {
          appeals?: Json
          channels?: Json
          created_at?: string
          id?: string
          owner_id?: string
          quiet_hours?: Json
          sessions?: Json
          tasks?: Json
          updated_at?: string
        }
        Relationships: []
      }
      notifications: {
        Row: {
          category: string | null
          created_at: string
          id: string
          is_read: boolean
          link: string | null
          message: string | null
          office_id: string | null
          title: string
          user_id: string | null
        }
        Insert: {
          category?: string | null
          created_at?: string
          id?: string
          is_read?: boolean
          link?: string | null
          message?: string | null
          office_id?: string | null
          title: string
          user_id?: string | null
        }
        Update: {
          category?: string | null
          created_at?: string
          id?: string
          is_read?: boolean
          link?: string | null
          message?: string | null
          office_id?: string | null
          title?: string
          user_id?: string | null
        }
        Relationships: []
      }
      office_settings: {
        Row: {
          created_at: string
          employee_welcome_template: string | null
          owner_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          employee_welcome_template?: string | null
          owner_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          employee_welcome_template?: string | null
          owner_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      portal_messages: {
        Row: {
          case_id: string | null
          client_id: string
          created_at: string
          id: string
          is_read: boolean
          message: string
          owner_id: string
          parent_id: string | null
          read_at: string | null
          sender_id: string | null
          sender_role: string
          subject: string | null
        }
        Insert: {
          case_id?: string | null
          client_id: string
          created_at?: string
          id?: string
          is_read?: boolean
          message: string
          owner_id: string
          parent_id?: string | null
          read_at?: string | null
          sender_id?: string | null
          sender_role: string
          subject?: string | null
        }
        Update: {
          case_id?: string | null
          client_id?: string
          created_at?: string
          id?: string
          is_read?: boolean
          message?: string
          owner_id?: string
          parent_id?: string | null
          read_at?: string | null
          sender_id?: string | null
          sender_role?: string
          subject?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "portal_messages_case_id_fkey"
            columns: ["case_id"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "portal_messages_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "portal_messages_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "portal_messages"
            referencedColumns: ["id"]
          },
        ]
      }
      powers_of_attorney: {
        Row: {
          agent_id_number: string | null
          agent_name: string | null
          client_id: string | null
          created_at: string
          expiry_date: string | null
          id: string
          issue_date: string | null
          issuer_id_number: string | null
          issuer_name: string | null
          najiz_id: string | null
          najiz_synced_at: string | null
          notes: string | null
          owner_id: string
          scope: string | null
          status: Database["public"]["Enums"]["wakalah_status"]
          updated_at: string
          wakalah_number: string
        }
        Insert: {
          agent_id_number?: string | null
          agent_name?: string | null
          client_id?: string | null
          created_at?: string
          expiry_date?: string | null
          id?: string
          issue_date?: string | null
          issuer_id_number?: string | null
          issuer_name?: string | null
          najiz_id?: string | null
          najiz_synced_at?: string | null
          notes?: string | null
          owner_id: string
          scope?: string | null
          status?: Database["public"]["Enums"]["wakalah_status"]
          updated_at?: string
          wakalah_number: string
        }
        Update: {
          agent_id_number?: string | null
          agent_name?: string | null
          client_id?: string | null
          created_at?: string
          expiry_date?: string | null
          id?: string
          issue_date?: string | null
          issuer_id_number?: string | null
          issuer_name?: string | null
          najiz_id?: string | null
          najiz_synced_at?: string | null
          notes?: string | null
          owner_id?: string
          scope?: string | null
          status?: Database["public"]["Enums"]["wakalah_status"]
          updated_at?: string
          wakalah_number?: string
        }
        Relationships: [
          {
            foreignKeyName: "powers_of_attorney_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          email: string | null
          full_name: string | null
          id: string
          phone: string | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          email?: string | null
          full_name?: string | null
          id: string
          phone?: string | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          email?: string | null
          full_name?: string | null
          id?: string
          phone?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      saved_filters: {
        Row: {
          created_at: string
          filters: Json
          id: string
          is_default: boolean
          name: string
          owner_id: string
          scope: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          filters?: Json
          id?: string
          is_default?: boolean
          name: string
          owner_id: string
          scope: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          filters?: Json
          id?: string
          is_default?: boolean
          name?: string
          owner_id?: string
          scope?: string
          updated_at?: string
        }
        Relationships: []
      }
      secure_secrets: {
        Row: {
          ciphertext: string
          created_at: string
          id: string
          iv: string
          key: string
          metadata: Json
          owner_id: string
          scope: string
          updated_at: string
        }
        Insert: {
          ciphertext: string
          created_at?: string
          id?: string
          iv: string
          key: string
          metadata?: Json
          owner_id: string
          scope: string
          updated_at?: string
        }
        Update: {
          ciphertext?: string
          created_at?: string
          id?: string
          iv?: string
          key?: string
          metadata?: Json
          owner_id?: string
          scope?: string
          updated_at?: string
        }
        Relationships: []
      }
      session_reminders: {
        Row: {
          created_at: string
          error: string | null
          id: string
          lead_hours: number
          owner_id: string
          sent_at: string | null
          session_id: string
          status: string
        }
        Insert: {
          created_at?: string
          error?: string | null
          id?: string
          lead_hours: number
          owner_id: string
          sent_at?: string | null
          session_id: string
          status?: string
        }
        Update: {
          created_at?: string
          error?: string | null
          id?: string
          lead_hours?: number
          owner_id?: string
          sent_at?: string | null
          session_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "session_reminders_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      sessions: {
        Row: {
          appeal_deadline: string | null
          case_id: string
          court: string | null
          created_at: string
          id: string
          location: string | null
          notes: string | null
          outcome: string | null
          owner_id: string
          room: string | null
          session_date: string
          status: Database["public"]["Enums"]["session_status"]
          updated_at: string
        }
        Insert: {
          appeal_deadline?: string | null
          case_id: string
          court?: string | null
          created_at?: string
          id?: string
          location?: string | null
          notes?: string | null
          outcome?: string | null
          owner_id: string
          room?: string | null
          session_date: string
          status?: Database["public"]["Enums"]["session_status"]
          updated_at?: string
        }
        Update: {
          appeal_deadline?: string | null
          case_id?: string
          court?: string | null
          created_at?: string
          id?: string
          location?: string | null
          notes?: string | null
          outcome?: string | null
          owner_id?: string
          room?: string | null
          session_date?: string
          status?: Database["public"]["Enums"]["session_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sessions_case_id_fkey"
            columns: ["case_id"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
        ]
      }
      sync_tokens: {
        Row: {
          created_at: string
          expires_at: string | null
          id: string
          is_revoked: boolean
          label: string | null
          last_used_at: string | null
          owner_id: string
          token_hash: string
        }
        Insert: {
          created_at?: string
          expires_at?: string | null
          id?: string
          is_revoked?: boolean
          label?: string | null
          last_used_at?: string | null
          owner_id: string
          token_hash: string
        }
        Update: {
          created_at?: string
          expires_at?: string | null
          id?: string
          is_revoked?: boolean
          label?: string | null
          last_used_at?: string | null
          owner_id?: string
          token_hash?: string
        }
        Relationships: []
      }
      task_reminders: {
        Row: {
          created_at: string
          employee_id: string | null
          error: string | null
          id: string
          lead_hours: number
          owner_id: string
          sent_at: string | null
          status: string
          task_id: string
        }
        Insert: {
          created_at?: string
          employee_id?: string | null
          error?: string | null
          id?: string
          lead_hours: number
          owner_id: string
          sent_at?: string | null
          status?: string
          task_id: string
        }
        Update: {
          created_at?: string
          employee_id?: string | null
          error?: string | null
          id?: string
          lead_hours?: number
          owner_id?: string
          sent_at?: string | null
          status?: string
          task_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_reminders_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_reminders_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
        ]
      }
      tasks: {
        Row: {
          case_id: string | null
          completed_at: string | null
          created_at: string
          description: string | null
          due_date: string | null
          employee_id: string | null
          id: string
          owner_id: string
          priority: Database["public"]["Enums"]["task_priority"]
          status: Database["public"]["Enums"]["task_status"]
          title: string
          updated_at: string
        }
        Insert: {
          case_id?: string | null
          completed_at?: string | null
          created_at?: string
          description?: string | null
          due_date?: string | null
          employee_id?: string | null
          id?: string
          owner_id: string
          priority?: Database["public"]["Enums"]["task_priority"]
          status?: Database["public"]["Enums"]["task_status"]
          title: string
          updated_at?: string
        }
        Update: {
          case_id?: string | null
          completed_at?: string | null
          created_at?: string
          description?: string | null
          due_date?: string | null
          employee_id?: string | null
          id?: string
          owner_id?: string
          priority?: Database["public"]["Enums"]["task_priority"]
          status?: Database["public"]["Enums"]["task_status"]
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tasks_case_id_fkey"
            columns: ["case_id"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
        ]
      }
      user_preferences: {
        Row: {
          created_at: string
          dashboard_cards: Json
          sidebar_collapsed: boolean
          sidebar_width: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          dashboard_cards?: Json
          sidebar_collapsed?: boolean
          sidebar_width?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          dashboard_cards?: Json
          sidebar_collapsed?: boolean
          sidebar_width?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      welcome_template_audit: {
        Row: {
          changed_by: string | null
          created_at: string
          id: string
          new_template: string | null
          old_template: string | null
          owner_id: string
        }
        Insert: {
          changed_by?: string | null
          created_at?: string
          id?: string
          new_template?: string | null
          old_template?: string | null
          owner_id: string
        }
        Update: {
          changed_by?: string | null
          created_at?: string
          id?: string
          new_template?: string | null
          old_template?: string | null
          owner_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      can_access_case_doc_object: {
        Args: { _name: string; _user_id: string }
        Returns: boolean
      }
      can_access_case_doc_path: {
        Args: { _path: string; _user_id: string }
        Returns: boolean
      }
      employee_can_access_case: {
        Args: { _case_id: string; _user_id: string }
        Returns: boolean
      }
      employee_can_access_client: {
        Args: { _client_id: string; _user_id: string }
        Returns: boolean
      }
      enqueue_session_reminders: { Args: never; Returns: number }
      enqueue_task_reminders: { Args: never; Returns: number }
      get_cron_jobs_status: { Args: never; Returns: Json }
      get_employee_portal_code: {
        Args: { _employee_id: string }
        Returns: string
      }
      get_employees_directory: {
        Args: never
        Returns: {
          full_name: string
          id: string
          job_title: string
          owner_id: string
          user_id: string
        }[]
      }
      has_doc_permission:
        | {
            Args: {
              _case_id: string
              _perm: Database["public"]["Enums"]["doc_permission"]
              _user_id: string
            }
            Returns: boolean
          }
        | {
            Args: {
              _case_id: string
              _perm: Database["public"]["Enums"]["doc_permission"]
              _user_id: string
            }
            Returns: boolean
          }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_office_member: { Args: { _owner_uuid: string }; Returns: boolean }
      link_current_user_to_portal: {
        Args: { _access_code?: string; _account_type?: string }
        Returns: Json
      }
      system_check_inspect: { Args: never; Returns: Json }
    }
    Enums: {
      app_role: "admin" | "lawyer" | "employee" | "client"
      case_status:
        | "open"
        | "in_study"
        | "closed_final"
        | "closed_non_final"
        | "appealed"
        | "archived"
      case_type:
        | "labor"
        | "commercial"
        | "execution"
        | "civil"
        | "personal_status"
        | "administrative"
        | "criminal"
        | "other"
      doc_permission: "view" | "upload" | "delete" | "manage"
      document_type:
        | "lawsuit"
        | "judgment_final"
        | "judgment_non_final"
        | "appeal_judgment"
        | "memorandum_reply"
        | "session_minutes"
        | "power_of_attorney"
        | "evidence"
        | "other"
      execution_status: "pending" | "in_progress" | "completed" | "rejected"
      notification_channel: "whatsapp" | "sms" | "email"
      notification_status:
        | "draft"
        | "scheduled"
        | "sent"
        | "failed"
        | "cancelled"
      session_status: "scheduled" | "held" | "postponed" | "cancelled"
      task_priority: "low" | "medium" | "high" | "urgent"
      task_status: "todo" | "in_progress" | "done" | "overdue"
      wakalah_status: "active" | "expired" | "revoked"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      app_role: ["admin", "lawyer", "employee", "client"],
      case_status: [
        "open",
        "in_study",
        "closed_final",
        "closed_non_final",
        "appealed",
        "archived",
      ],
      case_type: [
        "labor",
        "commercial",
        "execution",
        "civil",
        "personal_status",
        "administrative",
        "criminal",
        "other",
      ],
      doc_permission: ["view", "upload", "delete", "manage"],
      document_type: [
        "lawsuit",
        "judgment_final",
        "judgment_non_final",
        "appeal_judgment",
        "memorandum_reply",
        "session_minutes",
        "power_of_attorney",
        "evidence",
        "other",
      ],
      execution_status: ["pending", "in_progress", "completed", "rejected"],
      notification_channel: ["whatsapp", "sms", "email"],
      notification_status: [
        "draft",
        "scheduled",
        "sent",
        "failed",
        "cancelled",
      ],
      session_status: ["scheduled", "held", "postponed", "cancelled"],
      task_priority: ["low", "medium", "high", "urgent"],
      task_status: ["todo", "in_progress", "done", "overdue"],
      wakalah_status: ["active", "expired", "revoked"],
    },
  },
} as const
