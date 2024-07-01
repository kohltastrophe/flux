export type Function = (...any) -> ...any
export type Dict<T> = { [T]: any }
export type Set<T> = { [T]: boolean }
export type Symbol = { type: "Symbol" }

export type New<Name, Class> = (Name) -> (Class & Dict<any>) -> Class
export type Constructor =
	(<T>(T & Instance) -> (T & Dict<any>) -> T)
	& New<"Folder", Folder>
	& New<"BillboardGui", BillboardGui>
	& New<"CanvasGroup", CanvasGroup>
	& New<"Frame", Frame>
	& New<"ImageButton", ImageButton>
	& New<"ImageLabel", ImageLabel>
	& New<"ScreenGui", ScreenGui>
	& New<"ScrollingFrame", ScrollingFrame>
	& New<"SurfaceGui", SurfaceGui>
	& New<"TextBox", TextBox>
	& New<"TextButton", TextButton>
	& New<"TextLabel", TextLabel>
	& New<"UIAspectRatioConstraint", UIAspectRatioConstraint>
	& New<"UICorner", UICorner>
	& New<"UIGradient", UIGradient>
	& New<"UIGridLayout", UIGridLayout>
	& New<"UIListLayout", UIListLayout>
	& New<"UIPadding", UIPadding>
	& New<"UIPageLayout", UIPageLayout>
	& New<"UIScale", UIScale>
	& New<"UISizeConstraint", UISizeConstraint>
	& New<"UIStroke", UIStroke>
	& New<"UITableLayout", UITableLayout>
	& New<"UITextSizeConstraint", UITextSizeConstraint>
	& New<"VideoFrame", VideoFrame>
	& New<"ViewportFrame", ViewportFrame>
	& New<string, Instance>

return nil
