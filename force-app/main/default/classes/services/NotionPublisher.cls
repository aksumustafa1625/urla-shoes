/**
 * Publishes STAR-format (Situation / Task / Action / Result) interview-prep entries
 * to Notion as child pages under a configured parent page.
 *
 * Page layout per entry:
 *   ▼ Situation (heading_2 toggle)
 *       ### Context, ### Problem
 *   ▼ Task (heading_2 toggle)
 *       ### Goal, ### Constraints, ### Success Criteria
 *   ▼ Action (heading_2 toggle)
 *       ### Approach, ### Implementation (bullets), ### Code (code block)
 *   ▼ Result (heading_2 toggle)
 *       ### Outcome, ### Trade-offs & Lessons Learned,
 *       ### References (bullets), ### Future Work
 *
 * One callout per entry — all blocks nested ≤ 2 levels (Notion's single-request limit).
 *
 * Config: Notion_Config__c (Hierarchy custom setting)
 *   Token__c          — Notion integration secret (Bearer auth)
 *   Parent_Page_Id__c — 32-char page id from share URL
 */
public with sharing class NotionPublisher {

    private static final String NOTION_API_VERSION = '2022-06-28';
    private static final String NOTION_PAGES_ENDPOINT = 'https://api.notion.com/v1/pages';

    public class StarEntry {
        public String title;
        public String context;
        public String problem;
        public String goal;
        public String constraints;
        public String successCriteria;
        public String approach;
        public List<String> implementation;
        public String codeLanguage; // 'apex', 'javascript', 'bash', 'html', 'json', 'xml'
        public String codeSnippet;
        public String outcome;
        public String tradeOffs;
        public List<String> references;
        public String futureWork;
    }

    public class PublishResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String notionPageId;
        @AuraEnabled public String notionUrl;
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public String errorBody;
    }

    public class NotionPublisherException extends Exception {}

    /**
     * Publishes a single STAR entry to Notion. Returns PublishResult with success flag
     * and Notion page id/url on success, or error body on failure.
     */
    public static PublishResult publish(StarEntry entry) {
        if (entry == null || String.isBlank(entry.title)) {
            throw new NotionPublisherException('StarEntry.title is required');
        }

        Notion_Config__c cfg = Notion_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.Token__c) || String.isBlank(cfg.Parent_Page_Id__c)) {
            throw new NotionPublisherException(
                'Notion_Config__c is not configured. Set Token__c and Parent_Page_Id__c in Setup → Custom Settings → Notion Config → Manage.'
            );
        }

        String body = buildPageJson(entry, cfg.Parent_Page_Id__c);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NOTION_PAGES_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + cfg.Token__c);
        req.setHeader('Notion-Version', NOTION_API_VERSION);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(60000);
        req.setBody(body);

        Http http = new Http();
        HttpResponse res = http.send(req);

        PublishResult out = new PublishResult();
        out.statusCode = res.getStatusCode();
        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            out.success = true;
            out.notionPageId = (String) resp.get('id');
            out.notionUrl = (String) resp.get('url');
        } else {
            out.success = false;
            out.errorBody = res.getBody();
        }
        return out;
    }

    @AuraEnabled
    public static PublishResult publishFromJson(String entryJson) {
        StarEntry entry = (StarEntry) JSON.deserialize(entryJson, StarEntry.class);
        return publish(entry);
    }

    /* ─── JSON BUILDERS ─────────────────────────────────────────────────── */

    private static String buildPageJson(StarEntry e, String parentPageId) {
        Map<String, Object> page = new Map<String, Object>();
        page.put('parent', new Map<String, Object>{ 'page_id' => parentPageId });
        page.put('properties', new Map<String, Object>{
            'title' => new List<Object>{
                new Map<String, Object>{ 'text' => new Map<String, Object>{ 'content' => e.title } }
            }
        });
        page.put('children', buildChildren(e));
        return JSON.serialize(page, true);
    }

    private static List<Object> buildChildren(StarEntry e) {
        List<Object> blocks = new List<Object>();
        blocks.add(starSection('Situation', buildSituationContent(e)));
        blocks.add(starSection('Task', buildTaskContent(e)));
        blocks.add(starSection('Action', buildActionContent(e)));
        blocks.add(starSection('Result', buildResultContent(e)));
        return blocks;
    }

    private static List<Object> buildSituationContent(StarEntry e) {
        List<Object> kids = new List<Object>();
        addLabeledParagraph(kids, 'Context', e.context);
        addLabeledParagraph(kids, 'Problem', e.problem);
        return kids;
    }

    private static List<Object> buildTaskContent(StarEntry e) {
        List<Object> kids = new List<Object>();
        addLabeledParagraph(kids, 'Goal', e.goal);
        addLabeledParagraph(kids, 'Constraints', e.constraints);
        addLabeledParagraph(kids, 'Success Criteria', e.successCriteria);
        return kids;
    }

    private static List<Object> buildActionContent(StarEntry e) {
        List<Object> kids = new List<Object>();
        addLabeledParagraph(kids, 'Approach', e.approach);
        if (e.implementation != null && !e.implementation.isEmpty()) {
            kids.add(heading3('Implementation'));
            for (String item : e.implementation) {
                kids.add(bulletItem(item));
            }
        }
        if (String.isNotBlank(e.codeSnippet)) {
            kids.add(heading3('Code'));
            kids.add(codeBlock(e.codeSnippet, e.codeLanguage));
        }
        return kids;
    }

    private static List<Object> buildResultContent(StarEntry e) {
        List<Object> kids = new List<Object>();
        addLabeledParagraph(kids, 'Outcome', e.outcome);
        addLabeledParagraph(kids, 'Trade-offs & Lessons Learned', e.tradeOffs);
        if (e.references != null && !e.references.isEmpty()) {
            kids.add(heading3('References'));
            for (String ref : e.references) {
                kids.add(bulletItem(ref));
            }
        }
        addLabeledParagraph(kids, 'Future Work', e.futureWork);
        return kids;
    }

    private static void addLabeledParagraph(List<Object> kids, String label, String text) {
        if (String.isBlank(text)) {
            return;
        }
        kids.add(heading3(label));
        kids.add(paragraph(text));
    }

    /* ─── BLOCK FACTORIES (Notion block JSON shapes) ────────────────────── */

    // Use a plain `toggle` block (not `heading_2 + is_toggleable`) so the
    // Situation/Task/Action/Result labels render compact — same visual weight
    // as the reference design rather than large H2 headings.
    private static Map<String, Object> starSection(String name, List<Object> children) {
        return new Map<String, Object>{
            'object' => 'block',
            'type' => 'toggle',
            'toggle' => new Map<String, Object>{
                'rich_text' => richText(name),
                'color' => 'default',
                'children' => children
            }
        };
    }

    private static Map<String, Object> heading3(String text) {
        return new Map<String, Object>{
            'object' => 'block',
            'type' => 'heading_3',
            'heading_3' => new Map<String, Object>{
                'rich_text' => richText(text),
                'is_toggleable' => false,
                'color' => 'default'
            }
        };
    }

    private static Map<String, Object> paragraph(String text) {
        return new Map<String, Object>{
            'object' => 'block',
            'type' => 'paragraph',
            'paragraph' => new Map<String, Object>{
                'rich_text' => richTextChunks(text)
            }
        };
    }

    private static Map<String, Object> bulletItem(String text) {
        return new Map<String, Object>{
            'object' => 'block',
            'type' => 'bulleted_list_item',
            'bulleted_list_item' => new Map<String, Object>{
                'rich_text' => richTextChunks(text)
            }
        };
    }

    private static Map<String, Object> codeBlock(String content, String language) {
        return new Map<String, Object>{
            'object' => 'block',
            'type' => 'code',
            'code' => new Map<String, Object>{
                'rich_text' => richTextChunks(content),
                'language' => normalizeNotionLanguage(language)
            }
        };
    }

    // Notion's code-block language field accepts only a fixed whitelist. Aliases
    // map our domain language tokens ('apex', 'soql', 'visualforce') to the
    // closest Notion-supported value; unknown tokens fall back to 'plain text'.
    private static final Set<String> NOTION_LANGS = new Set<String>{
        'abap','abc','agda','arduino','ascii art','assembly','bash','basic','bnf',
        'c','c#','c++','clojure','coffeescript','coq','css','dart','dhall','diff',
        'docker','ebnf','elixir','elm','erlang','f#','flow','fortran','gherkin',
        'glsl','go','graphql','groovy','haskell','hcl','html','idris','java',
        'javascript','json','julia','kotlin','latex','less','lisp','livescript',
        'llvm ir','lua','makefile','markdown','markup','matlab','mathematica',
        'mermaid','nix','notion formula','objective-c','ocaml','pascal','perl',
        'php','plain text','powershell','prolog','protobuf','purescript','python',
        'r','racket','reason','ruby','rust','sass','scala','scheme','scss','shell',
        'smalltalk','solidity','sql','swift','toml','typescript','vb.net','verilog',
        'vhdl','visual basic','webassembly','xml','yaml','java/c/c++/c#'
    };

    private static final Map<String, String> LANG_ALIASES = new Map<String, String>{
        'apex' => 'java',
        'soql' => 'sql',
        'sosl' => 'sql',
        'vf' => 'html',
        'visualforce' => 'html',
        'lwc' => 'javascript',
        'js' => 'javascript',
        'ts' => 'typescript',
        'py' => 'python'
    };

    private static String normalizeNotionLanguage(String language) {
        if (String.isBlank(language)) {
            return 'plain text';
        }
        String lower = language.toLowerCase();
        if (LANG_ALIASES.containsKey(lower)) {
            return LANG_ALIASES.get(lower);
        }
        return NOTION_LANGS.contains(lower) ? lower : 'plain text';
    }

    private static List<Object> richText(String text) {
        return new List<Object>{
            new Map<String, Object>{
                'type' => 'text',
                'text' => new Map<String, Object>{ 'content' => text == null ? '' : text }
            }
        };
    }

    /**
     * Notion enforces a 2000-char limit per rich_text element. Long content
     * (code snippets especially) is chunked into multiple rich_text entries
     * so the entire block still renders as one paragraph/code block.
     */
    private static List<Object> richTextChunks(String text) {
        List<Object> chunks = new List<Object>();
        if (text == null) {
            chunks.add(new Map<String, Object>{
                'type' => 'text',
                'text' => new Map<String, Object>{ 'content' => '' }
            });
            return chunks;
        }
        Integer chunkSize = 1900;
        Integer pos = 0;
        while (pos < text.length()) {
            Integer endIdx = Math.min(pos + chunkSize, text.length());
            String slice = text.substring(pos, endIdx);
            chunks.add(new Map<String, Object>{
                'type' => 'text',
                'text' => new Map<String, Object>{ 'content' => slice }
            });
            pos = endIdx;
        }
        if (chunks.isEmpty()) {
            chunks.add(new Map<String, Object>{
                'type' => 'text',
                'text' => new Map<String, Object>{ 'content' => '' }
            });
        }
        return chunks;
    }
}
