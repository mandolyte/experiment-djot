local djot = require("djot")
local ast = require("djot.ast")
local insert_attribute, copy_attributes =
  ast.insert_attribute, ast.copy_attributes
local emoji -- require this later, only if emoji encountered
local format = string.format
local find, gsub = string.find, string.gsub

-- Produce a copy of a table.
local function copy(tbl)
  local result = {}
  if tbl then
    for k,v in pairs(tbl) do
      local newv = v
      if type(v) == "table" then
        newv = copy(v)
      end
      result[k] = newv
    end
  end
  return result
end

local function to_text(node)
  local buffer = {}
  if node[1] == "str" then
    buffer[#buffer + 1] = node[2]
  elseif node[1] == "softbreak" then
    buffer[#buffer + 1] = " "
  elseif #node > 1 then
    for i=2,#node do
      buffer[#buffer + 1] = to_text(node[i])
    end
  end
  return table.concat(buffer)
end

local Renderer = {}

function Renderer:new()
  local state = {
    tight = false,
    footnotes = nil,
    references = nil
  }
  setmetatable(state, self)
  self.__index = self
  return state
end

local function to_attr(attr)
  if not attr then
    return nil
  end
  local result = copy(attr)
  result._keys = nil
  return result
end

function Renderer:with_optional_span(node, f)
  local base = f(self:render_children(node))
  if node.attr then
    return pandoc.Span(base, to_attr(node.attr))
  else
    return base
  end
end

function Renderer:with_optional_div(node, f)
  local base = f(self:render_children(node))
  if node.attr then
    return pandoc.Div(base, to_attr(node.attr))
  else
    return base
  end
end

function Renderer:render_children(node)
  local buff = {}
  if #node > 1 then
    local oldtight
    if node.tight ~= nil then
      oldtight = self.tight
      self.tight = node.tight
    end
    for i=2,#node do
      local elt = self[node[i][1]](self, node[i])
      if elt.__name == "Inlines" or elt.__name == "Blocks" then
        for i=1,#elt do
          buff[#buff + 1] = elt[i]
        end
      else
        buff[#buff + 1] = elt
      end
    end
    if node.tight ~= nil then
      self.tight = oldtight
    end
  end
  return buff
end

function Renderer:render(doc)
  self.footnotes = doc.footnotes
  self.references = doc.references
  return self[doc[1]](self, doc)
end

function Renderer:doc(node)
  return pandoc.Pandoc(self:render_children(node))
end

function Renderer:raw_block(node)
  return pandoc.RawBlock(node.format, node[2])
end

function Renderer:para(node)
  local constructor = pandoc.Para
  if self.tight then
    constructor = pandoc.Plain
  end
  return self:with_optional_div(node, constructor)
end

function Renderer:blockquote(node)
  return self:with_optional_div(node, pandoc.BlockQuote)
end

function Renderer:div(node)
  return pandoc.Div(self:render_children(node), to_attr(node.attr))
end

function Renderer:heading(node)
  return pandoc.Header(node.level, self:render_children(node), to_attr(node.attr))
end

function Renderer:thematic_break(node)
  if node.attr then
    return pandoc.Div(pandoc.HorizontalRule(), to_attr(node.attr))
  else
    return pandoc.HorizontalRule()
  end
end

function Renderer:code_block(node)
  local attr = copy(to_attr(node.attr))
  if not attr.class then
    attr.class = node.lang
  else
    attr.class = node.lang .. " " .. attr.class
  end
  return pandoc.CodeBlock(to_text(node):gsub("\n$",""), attr)
end

function Renderer:table(node)
  local rows = {}
  local headers = {}
  local caption = {}
  local aligns = nil
  local widths = nil
  for i=2,#node do
    local row = node[i]
    if row[1] == "caption" then
      caption = self:render_children(row)
    elseif row[1] == "row" then
      if not aligns then
        aligns = {}
        widths = {}
        for j=2,#row do
          local align = row[j].align
          if not align then
            aligns[j - 1] = "AlignDefault"
          elseif align == "center" then
              aligns[j - 1] = "AlignCenter"
          elseif align == "left" then
              aligns[j - 1] = "AlignLeft"
          elseif align == "right" then
              aligns[j - 1] = "AlignRight"
          end
          widths[j - 1] = 0
        end
      end
      local cells = self:render_children(row)
      if i == 2 and row.head then
        headers = cells
      else
        rows[#rows + 1] = cells
      end
    end
  end
  return pandoc.utils.from_simple_table(
           pandoc.SimpleTable(caption, aligns, widths, headers, rows))
end

function Renderer:cell(node)
  return { pandoc.Plain(self:render_children(node)) }
end

function Renderer:list(node)
  local sty = node.list_style
  if sty == "*" or sty == "+" or sty == "-" then
    return self:with_optional_div(node, pandoc.BulletList)
  elseif sty == "X" then
    return self:with_optional_div(node, pandoc.BulletList)
  elseif sty == ":" then
    return self:with_optional_div(node, pandoc.DefinitionList)
  else
    local start = 1
    local sty = "DefaultStyle"
    local delim = "DefaultDelim"
    if node.start and node.start > 1 then
      start = node.start
    end
    local list_type = gsub(node.list_style, "%p", "")
    if list_type == "a" then
      sty = "LowerAlpha"
    elseif list_type == "A" then
      sty = "UpperAlpha"
    elseif list_type == "i" then
      sty = "LowerRoman"
    elseif list_type == "I" then
      sty = "UpperRoman"
    end
    local list_delim = gsub(node.list_style, "%P", "")
    if list_delim == ")" then
      delim = "OneParen"
    elseif list_delim == "()" then
      delim = "TwoParens"
    end
    return self:with_optional_div(node, function(x)
                                    return pandoc.OrderedList(x,
                                       pandoc.ListAttributes(start, sty, delim))
                                    end)
  end
end

function Renderer:list_item(node)
  local children = self:render_children(node)
  if node.checkbox then
     local box = (node.checkbox == "checked" and "☒") or "☐"
     local tag = children[1].tag
     if tag == "Para" or tag == "Plain" then
       children[1].content:insert(1, pandoc.Space())
       children[1].content:insert(1, pandoc.Str(box))
     else
       children:insert(1, pandoc.Para{pandoc.Str(box), pandoc.Space()})
     end
  end
  return children
end

function Renderer:definition_list_item(node)
  local items = self:render_children(node)
  local term = items[1]
  table.remove(items, 1)
  return { term, items }
end

function Renderer:term(node)
  return self:render_children(node)
end

function Renderer:definition(node)
  return self:render_children(node)
end

function Renderer:reference_definition()
  return ""
end

function Renderer:footnote_reference(node)
  local label = node[2]
  local note = self.footnotes[label]
  if note then
    return pandoc.Note(self:render_children(note))
  else
    io.stderr:write("Note " .. label .. " not found.")
    return pandoc.Str("[^" .. label .. "]")
  end
end

function Renderer:raw_inline(node)
  return pandoc.RawInline(node.format, node[2])
end

function Renderer:str(node)
  -- add a span, if needed, to contain attribute on a bare string:
  if node.attr then
    return pandoc.Span(pandoc.Inlines(node[2]), to_attr(node.attr))
  else
    return pandoc.Inlines(node[2])
  end
end

function Renderer:softbreak()
  return pandoc.SoftBreak()
end

function Renderer:hardbreak()
  return pandoc.LineBreak()
end

function Renderer:nbsp()
  return pandoc.Str(" ")
end

function Renderer:verbatim(node)
  return pandoc.Code(to_text(node), to_attr(node.attr))
end

function Renderer:link(node)
  local attrs = {}
  local dest = node.destination
  if node.reference then
    local ref = self.references[node.reference]
    if ref then
      if ref.attributes then
        attrs = copy(ref.attributes)
      end
      dest = ref.destination
    else
      dest = "#" -- empty href is illegal
    end
  end
  -- link's attributes override reference's:
  copy_attributes(attrs, node.attr)
  local title = attrs.title
  attrs.title = nil
  return pandoc.Link(self:render_children(node), dest,
                     title, to_attr(attrs))
end

function Renderer:image(node)
  local attrs = {}
  local dest = node.destination
  if node.reference then
    local ref = self.references[node.reference]
    if ref then
      if ref.attributes then
        attrs = copy(ref.attributes)
      end
      dest = ref.destination
    else
      dest = "#" -- empty href is illegal
    end
  end
  -- image's attributes override reference's:
  copy_attributes(attrs, node.attr)
  return pandoc.Image(self:render_children(node), dest,
           title, to_attr(attrs))
end

function Renderer:span(node)
  return pandoc.Span(self:render_children(node), to_attr(node.attr))
end

function Renderer:mark(node)
  local attr = copy(node.attr)
  if attr.class then
    attr.class = "mark " .. attr.class
  else
    attr = { class = "mark" }
  end
  return pandoc.Span(self:render_children(node), to_attr(attr))
end

function Renderer:insert(node)
  local attr = copy(node.attr)
  if attr.class then
    attr.class = "insert " .. attr.class
  else
    attr = { class = "insert" }
  end
  return pandoc.Span(self:render_children(node), to_attr(attr))
end

function Renderer:delete(node)
  return self:with_optional_span(node, pandoc.Strikeout)
end

function Renderer:subscript(node)
  return self:with_optional_span(node, pandoc.Subscript)
end

function Renderer:superscript(node)
  return self:with_optional_span(node, pandoc.Superscript)
end

function Renderer:emph(node)
  return self:with_optional_span(node, pandoc.Emph)
end

function Renderer:strong(node)
  return self:with_optional_span(node, pandoc.Strong)
end

function Renderer:double_quoted(node)
  return self:with_optional_span(node,
           function(x) return pandoc.Quoted("DoubleQuote", x) end)
end

function Renderer:single_quoted(node)
  return self:with_optional_span(node,
           function(x) return pandoc.Quoted("SingleQuote", x) end)
end

function Renderer:left_double_quote()
  return "“"
end

function Renderer:right_double_quote()
  return "”"
end

function Renderer:left_single_quote()
  return "‘"
end

function Renderer:right_single_quote()
  return "’"
end

function Renderer:ellipses()
  return "…"
end

function Renderer:em_dash()
  return "—"
end

function Renderer:en_dash()
  return "–"
end

function Renderer:emoji(node)
  emoji = require("djot.emoji")
  local found = emoji[node[2]:sub(2,-2)]
  if found then
    return found
  else
    return node[2]
  end
end

function Renderer:math(node)
  local math_type = "InlineMath"
  if find(node.attr.class, "display") then
    math_type = "DisplayMath"
  end
  return pandoc.Math(math_type, to_text(node))
end

function Reader(input)
  local parser = djot.Parser:new(tostring(input))
  parser:parse()
  parser:build_ast()
  return Renderer:render(parser.ast)
end
