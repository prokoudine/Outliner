/*
* Copyright (c) 2019 (https://github.com/phase1geo/Outliner)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Trevor Williams <phase1geo@gmail.com>
*/

using Pango;
using Gdk;

public enum FormatTag {
  BOLD = 0,
  ITALICS,
  UNDERLINE,
  STRIKETHRU,
  COLOR,
  HILITE,
  URL,
  MATCH,
  SELECT,
  LENGTH;

  public string to_string() {
    switch( this ) {
      case BOLD       :  return( "bold" );
      case ITALICS    :  return( "italics" );
      case UNDERLINE  :  return( "underline" );
      case STRIKETHRU :  return( "strikethru" );
      case COLOR      :  return( "color" );
      case HILITE     :  return( "hilite" );
      case URL        :  return( "url" );
      case MATCH      :  return( "match" );
    }
    return( "bold" );
  }

  public static FormatTag from_string( string str ) {
    switch( str ) {
      case "bold"       :  return( BOLD );
      case "italics"    :  return( ITALICS );
      case "underline"  :  return( UNDERLINE );
      case "strikethru" :  return( STRIKETHRU );
      case "color"      :  return( COLOR );
      case "hilite"     :  return( HILITE );
      case "url"        :  return( URL );
      case "match"      :  return( MATCH );
    }
    return( LENGTH );
  }

}

/* Stores information for undo/redo operation on tags */
public class UndoTagInfo {
  public int     start { private set; get; }
  public int     end   { private set; get; }
  public int     tag   { private set; get; }
  public string? extra { private set; get; }
  public UndoTagInfo( int tag, int start, int end, string? extra ) {
    this.tag   = tag;
    this.start = start;
    this.end   = end;
    this.extra = extra;
  }
}

public class FormattedText {

  private class TagInfo {

    private class FormattedRange {
      public int     start { get; set; default = 0; }
      public int     end   { get; set; default = 0; }
      public string? extra { get; set; default = null; }
      public FormattedRange( int s, int e, string? x ) {
        start = s;
        end   = e;
        extra = x;
      }
      public FormattedRange.from_xml( Xml.Node* n ) {
        load( n );
      }
      public bool combine( int s, int e ) {
        bool changed = false;
        if( (s <= end) && (e > end) ) {
          end     = e;
          changed = true;
        }
        if( (s < start) && (e >= start) ) {
          start   = s;
          changed = true;
        }
        return( changed );
      }
      public Xml.Node* save() {
        Xml.Node* n = new Xml.Node( null, "range" );
        n->set_prop( "start", start.to_string() );
        n->set_prop( "end",   end.to_string() );
        if( extra != null ) {
          n->set_prop( "extra", extra );
        }
        return( n );
      }
      public void load( Xml.Node* n ) {
        string? s = n->get_prop( "start" );
        if( s != null ) {
          start = int.parse( s );
        }
        string? e = n->get_prop( "end" );
        if( e != null ) {
          end = int.parse( e );
        }
        extra = n->get_prop( "extra" );
      }
    }

    private Array<FormattedRange> _info;

    /* Default constructor */
    public TagInfo() {
      _info = new Array<FormattedRange>();
    }

    /* Copies the given TagInfo structure to this one */
    public void copy( TagInfo other ) {
      _info.remove_range( 0, _info.length );
      for( int i=0; i<other._info.length; i++ ) {
        var other_info = other._info.index( i );
        _info.append_val( new FormattedRange( other_info.start, other_info.end, other_info.extra ) );
      }
    }

    /* Returns true if this info array is empty */
    public bool is_empty() {
      return( _info.length == 0 );
    }

    public void adjust( int index, int length ) {
      for( int i=0; i<_info.length; i++ ) {
        var info = _info.index( i );
        if( index <= info.start ) {
          info.start += length;
          info.end   += length;
          if( info.end <= index ) {
            _info.remove_index( i );
          }
        } else if( index < info.end ) {
          info.end += length;
        }
      }
    }

    /* Adds the given range from this format type */
    public void add_tag( int start, int end, string? extra ) {
      for( int i=0; i<_info.length; i++ ) {
        if( (extra == null) && _info.index( i ).combine( start, end ) ) {
          return;
        }
      }
      _info.append_val( new FormattedRange( start, end, extra ) );
    }

    /* Replaces the given range(s) with the given range */
    public void replace_tag( int start, int end, string? extra ) {
      _info.remove_range( 0, _info.length );
      _info.append_val( new FormattedRange( start, end, extra ) );
    }

    /* Removes the given range from this format type */
    public void remove_tag( int start, int end ) {
      for( int i=((int)_info.length - 1); i>=0; i-- ) {
        var info = _info.index( i );
        if( (start < info.end) && (end > info.start) ) {
          if( start <= info.start ) {
            if( info.end <= end ) {
              _info.remove_index( i );
            } else {
              info.start = end;
            }
          } else {
            if( info.end > end ) {
              _info.append_val( new FormattedRange( end, info.end, info.extra ) );
            }
            info.end = start;
          }
        }
      }
    }

    /* Removes all ranges for this tag */
    public void remove_tag_all() {
      _info.remove_range( 0, _info.length );
    }

    /* Returns all tags found within the given range */
    public void get_tags_in_range( int tag, int start, int end, ref Array<UndoTagInfo> tags ) {
      for( int i=0; i<_info.length; i++ ) {
        var info = _info.index( i );
        if( (start < info.end) && (end > info.start) ) {
          tags.append_val( new UndoTagInfo( tag, info.start, info.end, info.extra ) );
        }
      }
    }

    /* Returns true if the given index contains this tag */
    public bool is_applied_at_index( int index ) {
      for( int i=0; i<_info.length; i++ ) {
        var info = _info.index( i );
        if( (info.start <= index) && (index < info.end) ) {
          return( true );
        }
      }
      return( false );
    }

    /*
     Returns true if the given range overlaps with any tag; otherwise,
     returns false.
    */
    public bool is_applied_in_range( int start, int end ) {
      for( int i=0; i<_info.length; i++ ) {
        var info = _info.index( i );
        if( (start < info.end) && (end > info.start) ) {
          return( true );
        }
      }
      return( false );
    }

    /* Inserts all of the attributes for this tag */
    public void get_attributes( int tag_index, ref AttrList attrs, TagAttrs[] tag ) {
      for( int i=0; i<_info.length; i++ ) {
        var info = _info.index( i );
        tag[tag_index].add_attrs( ref attrs, info.start, info.end, info.extra );
      }
    }

    /* Returns the extra data associated with the given cursor position */
    public string? get_extra( int index ) {
      for( int i=0; i<_info.length; i++ ) {
        var info = _info.index( i );
        if( (info.start <= index) && (index < info.end) ) {
          return( info.extra );
        }
      }
      return( null );
    }

    /* Returns the list of ranges this tag is associated with */
    public Xml.Node* save( string tag ) {
      Xml.Node* n = new Xml.Node( null, tag );
      for( int i=0; i<_info.length; i++ ) {
        var info = _info.index( i );
        n->add_child( info.save() );
      }
      return( n );
    }

    /* Loads the data from XML */
    public void load( Xml.Node* n ) {
      for( Xml.Node* it = n->children; it != null; it = it->next ) {
        if( (it->type == Xml.ElementType.ELEMENT_NODE) && (it->name == "range") ) {
          _info.append_val( new FormattedRange.from_xml( it ) );
        }
      }
    }

  }

  private class TagAttrs {
    public Array<Pango.Attribute> attrs;
    public TagAttrs() {
      attrs = new Array<Pango.Attribute>();
    }
    public virtual void add_attrs( ref AttrList list, int start, int end, string? extra ) {
      for( int i=0; i<attrs.length; i++ ) {
        var attr = attrs.index( i ).copy();
        attr.start_index = start;
        attr.end_index   = end;
        list.change( (owned)attr );
      }
    }
    protected RGBA get_color( string value ) {
      RGBA c = {1.0, 1.0, 1.0, 1.0};
      c.parse( value );
      return( c );
    }
  }

  private class BoldInfo : TagAttrs {
    public BoldInfo() {
      attrs.append_val( attr_weight_new( Weight.BOLD ) );
    }
  }

  private class ItalicsInfo : TagAttrs {
    public ItalicsInfo() {
      attrs.append_val( attr_style_new( Style.ITALIC ) );
    }
  }

  private class UnderlineInfo : TagAttrs {
    public UnderlineInfo() {
      attrs.append_val( attr_underline_new( Underline.SINGLE ) );
    }
  }

  private class StrikeThruInfo : TagAttrs {
    public StrikeThruInfo() {
      attrs.append_val( attr_strikethrough_new( true ) );
    }
  }

  private class ColorInfo : TagAttrs {
    public ColorInfo() {}
    public override void add_attrs( ref AttrList list, int start, int end, string? extra ) {
      var color = get_color( extra );
      var attr  = attr_foreground_new( (uint16)(color.red * 65535), (uint16)(color.green * 65535), (uint16)(color.blue * 65535) );
      attr.start_index = start;
      attr.end_index   = end;
      list.change( (owned)attr );
    }
  }

  private class HighlightInfo : TagAttrs {
    public HighlightInfo() {}
    public override void add_attrs( ref AttrList list, int start, int end, string? extra ) {
      var color = get_color( extra );
      var bg    = attr_background_new( (uint16)(color.red * 65535), (uint16)(color.green * 65535), (uint16)(color.blue * 65535) );
      var alpha = attr_background_alpha_new( (uint16)(65536 * 0.5) );
      bg.start_index = start;
      bg.end_index   = end;
      list.change( (owned)bg );
      alpha.start_index = start;
      alpha.end_index   = end;
      list.change( (owned)alpha );
    }
  }

  private class UrlInfo : TagAttrs {
    public UrlInfo( RGBA color ) {
      set_color( color );
    }
    private void set_color( RGBA color ) {
      attrs.append_val( attr_foreground_new( (uint16)(color.red * 65535), (uint16)(color.green * 65535), (uint16)(color.blue * 65535) ) );
      attrs.append_val( attr_underline_new( Underline.SINGLE ) );
    }
    public void update_color( RGBA color ) {
      attrs.remove_range( 0, 2 );
      set_color( color );
    }

  }

  private class MatchInfo : TagAttrs {
    public MatchInfo( RGBA f, RGBA b ) {
      set_color( f, b );
    }
    private void set_color( RGBA f, RGBA b ) {
      attrs.append_val( attr_foreground_new( (uint16)(f.red * 65535), (uint16)(f.green * 65535), (uint16)(f.blue * 65535) ) );
      attrs.append_val( attr_background_new( (uint16)(b.red * 65535), (uint16)(b.green * 65535), (uint16)(b.blue * 65535) ) );
    }
    public void update_color( RGBA f, RGBA b ) {
      attrs.remove_range( 0, 2 );
      set_color( f, b );
    }
  }

  private class SelectInfo : TagAttrs {
    public SelectInfo( RGBA f, RGBA b ) {
      set_color( f, b );
    }
    private void set_color( RGBA f, RGBA b ) {
      attrs.append_val( attr_foreground_new( (uint16)(f.red * 65535), (uint16)(f.green * 65535), (uint16)(f.blue * 65535) ) );
      attrs.append_val( attr_background_new( (uint16)(b.red * 65535), (uint16)(b.green * 65535), (uint16)(b.blue * 65535) ) );
    }
    public void update_color( RGBA f, RGBA b ) {
      attrs.remove_range( 0, 2 );
      set_color( f, b );
    }
  }

  private static TagAttrs[] _attr_tags = null;
  private TagInfo[]         _formats   = new TagInfo[FormatTag.LENGTH];
  private string            _text      = "";

  public signal void changed();

  public string text {
    get {
      return( _text );
    }
  }

  public FormattedText( Theme theme ) {
    initialize( theme );
  }

  public FormattedText.with_text( Theme theme, string txt ) {
    initialize( theme );
    _text = txt;
  }

  /* Initializes this instance */
  private void initialize( Theme theme ) {
    if( _attr_tags == null ) {
      _attr_tags = new TagAttrs[FormatTag.LENGTH];
      _attr_tags[FormatTag.BOLD]       = new BoldInfo();
      _attr_tags[FormatTag.ITALICS]    = new ItalicsInfo();
      _attr_tags[FormatTag.UNDERLINE]  = new UnderlineInfo();
      _attr_tags[FormatTag.STRIKETHRU] = new StrikeThruInfo();
      _attr_tags[FormatTag.COLOR]      = new ColorInfo();
      _attr_tags[FormatTag.HILITE]     = new HighlightInfo();
      _attr_tags[FormatTag.URL]        = new UrlInfo( theme.url );
      _attr_tags[FormatTag.MATCH]      = new MatchInfo( theme.match_foreground, theme.match_background );
      _attr_tags[FormatTag.SELECT]     = new SelectInfo( theme.textsel_foreground, theme.textsel_background );
    }
    for( int i=0; i<FormatTag.LENGTH; i++ ) {
      _formats[i] = new TagInfo();
    }
  }

  public static void set_theme( Theme theme ) {
    if( _attr_tags == null ) return;
    (_attr_tags[FormatTag.URL] as UrlInfo).update_color( theme.url );
    (_attr_tags[FormatTag.MATCH] as MatchInfo).update_color( theme.match_foreground, theme.match_background );
    (_attr_tags[FormatTag.SELECT] as SelectInfo).update_color( theme.textsel_foreground, theme.textsel_background );
  }

  /* Copies the specified FormattedText instance to this one */
  public void copy( FormattedText other ) {
    _text = other._text;
    for( int i=0; i<FormatTag.LENGTH; i++ ) {
      _formats[i].copy( other._formats[i] );
    }
    changed();
  }

  /* Initializes the text to the given value */
  public void set_text( string str ) {
    _text = str;
  }

  /* Inserts a string into the given text */
  public void insert_text( int index, string str ) {
    _text = _text.splice( index, index, str );
    foreach( TagInfo f in _formats) {
      f.adjust( index, str.length );
    }
    changed();
  }

  /* Replaces the given text range with the given string */
  public void replace_text( int index, int chars, string str ) {
    _text = _text.splice( index, (index + chars), str );
    foreach( TagInfo f in _formats ) {
      f.remove_tag( index, (index + chars) );
      f.adjust( index, ((0 - chars) + str.length) );
    }
    changed();
  }

  /* Removes characters from the current text, starting at the given index */
  public void remove_text( int index, int chars ) {
    _text = _text.splice( index, (index + chars) );
    foreach( TagInfo f in _formats ) {
      f.remove_tag( index, (index + chars) );
      f.adjust( index, (0 - chars) );
    }
    changed();
  }

  /* Adds the given tag */
  public void add_tag( FormatTag tag, int start, int end, string? extra=null ) {
    _formats[tag].add_tag( start, end, extra );
    changed();
  }

  /* Replaces the given tag with the given range */
  public void replace_tag( FormatTag tag, int start, int end, string? extra=null ) {
    _formats[tag].replace_tag( start, end, extra );
    changed();
  }

  /* Removes the given tag */
  public void remove_tag( FormatTag tag, int start, int end ) {
    _formats[tag].remove_tag( start, end );
    changed();
  }

  /* Removes all ranges for the given tag */
  public void remove_tag_all( FormatTag tag ) {
    _formats[tag].remove_tag_all();
    changed();
  }

  /* Removes all formatting from the text */
  public void remove_all_tags( int start, int end ) {
    foreach( TagInfo f in _formats ) {
      f.remove_tag( start, end );
    }
    changed();
  }

  /* Returns true if the given tag is applied at the given index */
  public bool is_tag_applied_at_index( FormatTag tag, int index ) {
    return( _formats[tag].is_applied_at_index( index ) );
  }

  /* Returns true if the given tag is applied within the given range */
  public bool is_tag_applied_in_range( FormatTag tag, int start, int end ) {
    return( _formats[tag].is_applied_in_range( start, end ) );
  }

  /* Returns true if at least one tag is applied to the text */
  public bool tags_exist() {
    foreach( TagInfo f in _formats ) {
      if( !f.is_empty() ) {
        return( true );
      }
    }
    return( false );
  }

  /* Returns an array containing all tags that are within the specified range */
  public Array<UndoTagInfo> get_tags_in_range( int start, int end ) {
    var tags = new Array<UndoTagInfo>();
    for( int i=0; i<FormatTag.LENGTH-2; i++ ) {
      _formats[i].get_tags_in_range( i, start, end, ref tags );
    }
    return( tags );
  }

  /* Reapplies tags that were previously removed */
  public void apply_tags( Array<UndoTagInfo> tags ) {
    for( int i=((int)tags.length - 1); i>=0; i-- ) {
      var info = tags.index( i );
      _formats[info.tag].add_tag( info.start, info.end, info.extra );
    }
    changed();
  }

  /*
   Returns the Pango attribute list to apply to the Pango layout.  This
   method should only be called if tags_exist returns true.
  */
  public AttrList get_attributes() {
    var attrs = new AttrList();
    for( int i=0; i<FormatTag.LENGTH; i++ ) {
      _formats[i].get_attributes( i, ref attrs, _attr_tags );
    }
    return( attrs );
  }

  /*
   Returns the extra data stored at the given index location, if one exists.
   If nothing is found, returns null.
  */
  public string? get_extra( FormatTag tag, int index ) {
    return( _formats[tag].get_extra( index ) );
  }

  /*
   Performs search of the given string within the text.  If any occurrences
   are found, highlight them with the match color.
  */
  public bool do_search( string pattern, ref Array<int> starts ) {
    remove_tag_all( FormatTag.MATCH );
    if( (pattern != "") && text.contains( pattern ) ) {
      var tags = new Array<UndoTagInfo>();
      var index = 0;
      while( (index = text.index_of( pattern, index )) != -1 ) {
        var end = index + pattern.index_of_nth_char( pattern.length );
        tags.append_val( new UndoTagInfo( FormatTag.MATCH, index, end, null ) );
        starts.append_val( index );
        index++;
      }
      apply_tags( tags );
      return( true );
    }
    return( false );
  }

  /* Saves the text as the given XML node */
  public Xml.Node* save() {
    Xml.Node* n = new Xml.Node( null, "text" );
    n->new_prop( "data", text );
    for( int i=0; i<(FormatTag.LENGTH - 2); i++ ) {
      if( !_formats[i].is_empty() ) {
        var tag = (FormatTag)i;
        n->add_child( _formats[i].save( tag.to_string() ) );
      }
    }
    return( n );
  }

  /* Loads the given XML information */
  public void load( Xml.Node* n ) {
    string? t = n->get_prop( "data" );
    if( t != null ) {
      _text = t;
    }
    for( Xml.Node* it = n->children; it != null; it = it->next ) {
      if( it->type == Xml.ElementType.ELEMENT_NODE ) {
        var tag = FormatTag.from_string( it->name );
        if( tag != FormatTag.LENGTH ) {
          _formats[tag].load( it );
        }
      }
    }
    changed();
  }

}
