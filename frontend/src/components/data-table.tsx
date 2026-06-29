import { type ReactNode } from "react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Pencil, Trash2, Inbox } from "lucide-react";

export type Column<T> = {
  key: string;
  header: string;
  render?: (row: T) => ReactNode;
  className?: string;
};

export function DataTable<T extends { id: string }>({
  rows, columns, onEdit, onDelete, emptyTitle = "لا توجد بيانات بعد",
}: {
  rows: T[];
  columns: Column<T>[];
  onEdit?: (row: T) => void;
  onDelete?: (row: T) => void;
  emptyTitle?: string;
}) {
  if (rows.length === 0) {
    return (
      <Card className="card-3d border-none p-10 text-center">
        <div className="mx-auto h-16 w-16 rounded-2xl bg-muted grid place-items-center mb-3">
          <Inbox className="h-8 w-8 text-muted-foreground/50" />
        </div>
        <p className="text-sm text-muted-foreground">{emptyTitle}</p>
        <p className="text-xs text-muted-foreground/70 mt-1">اضغط زر "إضافة" أعلاه للبدء</p>
      </Card>
    );
  }

  return (
    <Card className="card-3d border-none overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-gradient-to-l from-primary/10 to-transparent">
            <tr>
              {columns.map((c) => (
                <th key={c.key} className={`px-4 py-3 text-right font-bold text-xs uppercase tracking-wider ${c.className ?? ""}`}>
                  {c.header}
                </th>
              ))}
              {(onEdit || onDelete) && <th className="px-4 py-3 text-right">إجراءات</th>}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, i) => (
              <tr key={row.id} className={`border-t border-border/50 hover:bg-muted/40 transition-colors ${i % 2 === 0 ? "" : "bg-muted/20"}`}>
                {columns.map((c) => (
                  <td key={c.key} className={`px-4 py-3 text-right ${c.className ?? ""}`}>
                    {c.render ? c.render(row) : (row as any)[c.key] ?? "—"}
                  </td>
                ))}
                {(onEdit || onDelete) && (
                  <td className="px-4 py-3 text-right">
                    <div className="flex gap-1 justify-end">
                      {onEdit && (
                        <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => onEdit(row)}>
                          <Pencil className="h-3.5 w-3.5" />
                        </Button>
                      )}
                      {onDelete && (
                        <Button variant="ghost" size="icon" className="h-8 w-8 text-destructive hover:text-destructive" onClick={() => {
                          if (confirm("هل أنت متأكد من الحذف؟")) onDelete(row);
                        }}>
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      )}
                    </div>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}
