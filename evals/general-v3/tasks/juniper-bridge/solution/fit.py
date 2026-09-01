"""Shared geometric-model fits for juniper-bridge (competency C-b2fceb71).
Used by the fixture generator to derive ground-truth inlier counts, by the
oracle as one valid implementation, and by the verifier. Deterministic."""
import numpy as np
import cv2


def line_truth(pts, th=2.0, iters=800, seed=7):
    """RANSAC best line over (x, y) points. Returns (model, inliers)."""
    r = np.random.RandomState(seed)
    best = 0; model = None
    n = len(pts)
    for _ in range(iters):
        i, j = r.choice(n, 2, replace=False)
        p1, p2 = pts[i], pts[j]
        dx = p2[0]-p1[0]
        if abs(dx) < 1e-6:
            continue
        m = (p2[1]-p1[1])/dx
        b = p1[1]-m*p1[0]
        dist = np.abs(m*pts[:, 0]-pts[:, 1]+b)/np.sqrt(m*m+1)
        cnt = int((dist < th).sum())
        if cnt > best:
            best = cnt; model = (round(float(m), 5), round(float(b), 5))
    return model, best


def plane_truth(a_img, b_img, ransac_th=4.0, max_match=500):
    """ORB feature matching + homography RANSAC; returns (inliers, n_match)."""
    orb = cv2.ORB_create(2000)
    ka, da = orb.detectAndCompute(a_img, None)
    kb, db = orb.detectAndCompute(b_img, None)
    if da is None or db is None or len(ka) < 8 or len(kb) < 8:
        return (0, 0)
    bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)
    try:
        matches = bf.match(da, db)
    except Exception:
        return (0, 0)
    matches = sorted(matches, key=lambda m: m.distance)[:max_match]
    if len(matches) < 8:
        return (0, len(matches))
    src = np.float32([ka[m.queryIdx].pt for m in matches]).reshape(-1, 1, 2)
    dst = np.float32([kb[m.trainIdx].pt for m in matches]).reshape(-1, 1, 2)
    H, mask = cv2.findHomography(src, dst, cv2.RANSAC, ransac_th)
    inliers = int(mask.sum()) if mask is not None else 0
    return (inliers, len(matches))


def rigid_truth(A, B, th=0.6, iters=1500, seed=11):
    """Robust rigid transform over matched correspondences. Returns
    (model(R,t), inliers)."""
    r = np.random.RandomState(seed)
    n = len(A); best = 0; bestRT = None
    for _ in range(iters):
        idx = r.choice(n, 2, replace=False)
        a1, a2 = A[idx[0]], A[idx[1]]
        b1, b2 = B[idx[0]], B[idx[1]]
        ra = a2-a1; rb = b2-b1
        lena = np.linalg.norm(ra); lenb = np.linalg.norm(rb)
        if lena < 1e-6 or lenb < 1e-6:
            continue
        cos = np.dot(ra, rb)/(lena*lenb)
        sin = (ra[0]*rb[1]-ra[1]*rb[0])/(lena*lenb)
        RR = np.array([[cos, -sin], [sin, cos]])
        tt = b1 - RR.dot(a1)
        err = B - (RR.dot(A.T).T + tt)
        dist = np.linalg.norm(err, axis=1)
        cnt = int((dist < th).sum())
        if cnt > best:
            best = cnt; bestRT = (RR, tt)
    return bestRT, best


def homography_model(a_img, b_img):
    """Return the recovered homography for cross-checking."""
    return plane_truth(a_img, b_img)[0] if False else None