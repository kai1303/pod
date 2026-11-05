import { useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { Check, MessageSquare, Send, Undo2 } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

export function CommentThread() {
  const [resolved, setResolved] = useState(false);
  const [draft, setDraft] = useState("");
  const [replies, setReplies] = useState<string[]>([]);
  const [error, setError] = useState("");
  const reduced = useReducedMotion();
  return (
    <Card className="pdf-component-card comment-card">
      <CardHeader className="pdf-card-header">
        <CardTitle>
          <MessageSquare className="size-4" />
          Review thread
        </CardTitle>
        <Badge variant={resolved ? "outline" : "secondary"}>
          {resolved ? "Resolved" : "Open"}
        </Badge>
      </CardHeader>
      <CardContent>
        <div className="comment-entry">
          <Avatar className="size-8">
            <AvatarFallback>DA</AvatarFallback>
          </Avatar>
          <div>
            <div className="comment-author">
              <strong>Demo author</strong>
              <span>Page 3</span>
            </div>
            <p>Could we make this heading easier to scan?</p>
            <span className="comment-meta">Sample comment · local preview</span>
          </div>
        </div>
        <div className="local-replies" aria-live="polite">
          <AnimatePresence initial={false}>
            {replies.map((reply, index) => (
              <motion.div
                key={index}
                className="comment-entry"
                initial={{ opacity: 0, y: reduced ? 0 : 5 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.14 }}
              >
                <Avatar className="size-7">
                  <AvatarFallback>YO</AvatarFallback>
                </Avatar>
                <div>
                  <div className="comment-author">
                    <strong>You</strong>
                    <span>Just now</span>
                  </div>
                  <p>{reply}</p>
                </div>
              </motion.div>
            ))}
          </AnimatePresence>
        </div>
        {resolved ? (
          <Alert className="thread-resolved">
            <Check className="size-4" />
            <AlertDescription>
              This preview thread is resolved.
            </AlertDescription>
          </Alert>
        ) : (
          <form
            className="comment-composer"
            onSubmit={(event) => {
              event.preventDefault();
              if (!draft.trim()) {
                setError("Write a reply before posting.");
                return;
              }
              setReplies([...replies, draft.trim()]);
              setDraft("");
              setError("");
            }}
          >
            <Label htmlFor="comment-reply">Reply</Label>
            <Textarea
              id="comment-reply"
              value={draft}
              onChange={(event) => {
                setDraft(event.target.value);
                setError("");
              }}
              placeholder="Add to the conversation…"
              maxLength={1000}
              rows={2}
              aria-invalid={!!error}
              aria-describedby={error ? "comment-reply-error" : undefined}
            />
            {error && (
              <p className="field-error" id="comment-reply-error" role="alert">
                {error}
              </p>
            )}
            <div className="comment-compose-footer">
              <span>{draft.length}/1000</span>
              <Button type="submit" size="sm">
                <Send />
                Post reply
              </Button>
            </div>
          </form>
        )}
        <div className="thread-footer">
          <span>
            {replies.length} {replies.length === 1 ? "reply" : "replies"}
          </span>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => {
              setResolved(!resolved);
              setError("");
            }}
          >
            {resolved ? <Undo2 /> : <Check />}
            {resolved ? "Reopen thread" : "Resolve thread"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
