Short VideoRenderer class that renders adds an array of OverlayRenderable overlays to a video
    OverlayRenderable is any UIView that provides a UIView with superView at given video playback percentage

    Library provides an OverlayRenderable protocol which can be used by consumers to make UIView's renderable with our VideoRenderer
    VideoRenderer class provides a way to export a given PHAsset with overlays to a URL in filesystem
    A helper class from VideoRenderer saves the generated video in Photos


## Instructions
* To render a video one must create a UIView conforming to OverlayRenderable
* OverlayRenderable instances that are about to be rendered must contain a superView
* To render a video use ``exportVideoAsset(phAsset: PHAsset,
                                       duration: Float,
                                       resolution: CGSize,
                                       overlays:[OverlayRenderable],
                                       completion:@escaping (URL?, Error?) -> ())``
* Successful call of this function will return a URL containing the rendered video
* If needed one can use ``saveVideoInPhotos(url:URL, completion: (() -> ())? = nil)`` with the resulting URL to save the resulting video in Photos

## Description
* OverlayRenderable instances are added on the video using their existing CGrects at the time of rendering
* For example if a OverlayRenderable with CGRect(x: 0, y: 0, width: 1920, height: 1080) is rendered on a video with provided size of 1920x1080 then the OverlayRenderable will cover the entire video
* If an Image PHAsset is used then a video is created from the still image with the given duration in seconds
* Max duration is 60s
