module SP
  autoload :PocketLinksRetriever, 'sp/middleware/pocket_links_retriever'
  autoload :Config, 'sp/middleware/config'
  autoload :Logger, 'sp/middleware/logger'
  autoload :Batcher, 'sp/middleware/batcher'
  autoload :PageParser, 'sp/middleware/page_parser'
  autoload :Indexer, 'sp/middleware/indexer'
  autoload :LegacyLinksLoader, 'sp/middleware/legacy_links_loader'
end
