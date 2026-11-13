import Foundation

/// Made-up web pages shaped like the real ones the app reads: only the parts the app uses
/// (the title and the description tags), with invented content.
enum SamplePages {
    /// A LinkedIn-style post: no real title, so the "title" is the post's opening, cut off,
    /// followed by the author and comment count. The description is the whole post.
    static let post = """
    <html><head>
    <title>Most teams ship features nobody asked for | Sam Rivera</title>
    <meta property="og:title" content="Most teams ship features nobody asked for. Here is how we stopped: we started every… | Sam Rivera | 12 comments">
    <meta property="og:description" content="Most teams ship features nobody asked for. Here is how we stopped: we started every project with five customer calls.

    What changed:

    - Fewer features &amp; better ones
    - Shorter roadmaps
    - Happier engineers 🚀

    Try it for one quarter.">
    </head><body></body></html>
    """

    /// A post whose title is only hashtags; its text is long enough to count as a post anyway.
    static let hashtagPost = """
    <html><head>
    <meta property="og:title" content="#product #design #ai | Sam Rivera | 3 comments">
    <meta property="og:description" content="AI makes it much easier to build software. \(String(repeating: "Here is what that means for product teams and the way they plan. ", count: 14))">
    </head></html>
    """

    /// A LinkedIn-style article: a real title, and a short description.
    static let article = """
    <html><head>
    <meta property="og:title" content="Interface Patterns | Sam Rivera">
    <meta property="og:description" content="A library of patterns for inventing new interfaces.">
    </head></html>
    """

    /// A Medium-style article: a long real headline and a subtitle.
    static let medium = """
    <html><head>
    <meta property="og:title" content="I Rebuilt Our Onboarding in 30 Days: Here&#39;s What Actually Moved Retention">
    <meta name="description" content="A practical walkthrough of the five changes that mattered, and the ten that didn’t.">
    </head></html>
    """

    /// A page with only a title tag.
    static let titleTagOnly = "<html><head><title>  Plain   Page\nTitle </title></head></html>"
}
