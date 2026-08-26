interface HighlightedCodeProps {
  html: string;
  caption: string;
}

export function HighlightedCode({ html, caption }: HighlightedCodeProps) {
  return (
    <figure className="highlighted-code">
      <figcaption className="sr-only">{caption}</figcaption>
      <div dangerouslySetInnerHTML={{ __html: html }} />
    </figure>
  );
}
