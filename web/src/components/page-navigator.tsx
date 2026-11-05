import { useState } from "react";
import { ChevronLeft, ChevronRight, Files } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Pagination,
  PaginationContent,
  PaginationItem,
  PaginationLink,
} from "@/components/ui/pagination";
import { ScrollArea } from "@/components/ui/scroll-area";

const pageCount = 24;
export function PageNavigator() {
  const [page, setPage] = useState(1);
  const [draft, setDraft] = useState("1");
  const [error, setError] = useState("");
  function choose(next: number) {
    setPage(next);
    setDraft(String(next));
    setError("");
  }
  const displayed = [...new Set([1, page, pageCount])];
  return (
    <Card className="pdf-component-card pages-card">
      <CardHeader className="pdf-card-header">
        <CardTitle>
          <Files className="size-4" />
          Pages
        </CardTitle>
        <Badge variant="secondary">{pageCount} pages</Badge>
      </CardHeader>
      <CardContent>
        <ScrollArea
          className="page-scroll"
          aria-label="Preview page thumbnails"
        >
          <div className="thumbnail-grid">
            {Array.from({ length: pageCount }, (_, index) => (
              <button
                type="button"
                className={
                  page === index + 1 ? "thumbnail is-current" : "thumbnail"
                }
                key={index}
                onClick={() => choose(index + 1)}
                aria-label={`Select page ${index + 1}`}
                aria-current={page === index + 1 ? "page" : undefined}
              >
                <span className="thumbnail-paper">
                  <span />
                  <span />
                  <span />
                  <span />
                  <span />
                </span>
                <span>{index + 1}</span>
              </button>
            ))}
          </div>
        </ScrollArea>
        <Pagination
          aria-label="Preview page navigation"
          className="preview-pagination"
        >
          <PaginationContent>
            <PaginationItem>
              <Button
                variant="ghost"
                size="icon-sm"
                aria-label="Previous preview page"
                disabled={page === 1}
                onClick={() => choose(page - 1)}
              >
                <ChevronLeft />
              </Button>
            </PaginationItem>
            {displayed.map((number) => (
              <PaginationItem key={number}>
                <PaginationLink
                  href="#pages"
                  size="icon-sm"
                  isActive={page === number}
                  aria-label={`Go to preview page ${number}`}
                  onClick={(event) => {
                    event.preventDefault();
                    choose(number);
                  }}
                >
                  {number}
                </PaginationLink>
              </PaginationItem>
            ))}
            <PaginationItem>
              <Button
                variant="ghost"
                size="icon-sm"
                aria-label="Next preview page"
                disabled={page === pageCount}
                onClick={() => choose(page + 1)}
              >
                <ChevronRight />
              </Button>
            </PaginationItem>
          </PaginationContent>
        </Pagination>
        <form
          className="page-jump"
          onSubmit={(event) => {
            event.preventDefault();
            const value = Number(draft);
            if (
              !/^\d+$/.test(draft) ||
              !Number.isInteger(value) ||
              value < 1 ||
              value > pageCount
            ) {
              setError(`Enter a page from 1 to ${pageCount}.`);
              return;
            }
            choose(value);
          }}
        >
          <Label htmlFor="jump-to-page">Go to page</Label>
          <Input
            id="jump-to-page"
            value={draft}
            onChange={(event) => {
              setDraft(event.target.value);
              setError("");
            }}
            inputMode="numeric"
            aria-invalid={!!error}
            aria-describedby={error ? "page-jump-error" : undefined}
            maxLength={4}
          />
          <span>of {pageCount}</span>
          <Button type="submit" size="sm" variant="outline">
            Go
          </Button>
        </form>
        {error && (
          <p className="field-error" id="page-jump-error" role="alert">
            {error}
          </p>
        )}
        <p className="page-preview-state" role="status">
          Previewing page {page} of {pageCount}
        </p>
      </CardContent>
    </Card>
  );
}
