use std::collections::{BTreeMap, HashMap};
use std::time::Instant;

use crate::macos::DisplayId;
use yashiki_ipc::OuterGap;

use super::{Rect, Tag, WindowId};

#[derive(Debug, Clone)]
pub struct Display {
    pub id: DisplayId,
    pub name: String,
    /// Usable area: the physical bounds minus what the menu bar reserves.
    pub frame: Rect,
    /// Physical bounds of the display.
    pub physical_frame: Rect,
    pub is_main: bool,
    pub visible_tags: Tag,
    pub previous_visible_tags: Tag,
    pub tag_orders: BTreeMap<u8, Vec<WindowId>>,
    /// Per-tag last-focused window with timestamp. Used to restore focus to the
    /// most recently-used window on a tag when switching back. For multi-bit
    /// visible_tags, the entry with the latest timestamp wins.
    pub last_focused_per_tag: HashMap<u8, (WindowId, Instant)>,
    pub current_layout: Option<String>,
    pub previous_layout: Option<String>,
    /// Overrides the global outer gap for this display. Needed when displays
    /// reserve different amounts at the top: a notched built-in panel keeps its
    /// menu bar strip even when the menu bar auto-hides, so a gap calibrated for
    /// an external display leaves a visible band there.
    pub outer_gap: Option<OuterGap>,
}

impl Display {
    pub fn new(
        id: DisplayId,
        name: String,
        frame: Rect,
        physical_frame: Rect,
        is_main: bool,
    ) -> Self {
        Self {
            id,
            name,
            frame,
            physical_frame,
            is_main,
            visible_tags: Tag::new(1),
            previous_visible_tags: Tag::new(1),
            tag_orders: BTreeMap::new(),
            last_focused_per_tag: HashMap::new(),
            current_layout: None,
            previous_layout: None,
            outer_gap: None,
        }
    }
}
